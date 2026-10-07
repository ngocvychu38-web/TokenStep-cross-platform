import Foundation
import Combine
import Security


protocol CloudPasswordStorage {
    func read(account: String) -> String?
    func save(_ password: String, account: String) -> Bool
    func delete(account: String)
}

struct CloudKeychainPasswordStorage: CloudPasswordStorage {
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.huangshu.TokenStep.supabase-login",
         kSecAttrAccount as String: account]
    }

    func read(account: String) -> String? {
        var attributes = query(account)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ password: String, account: String) -> Bool {
        let data = Data(password.utf8)
        let status = SecItemUpdate(query(account) as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var attributes = query(account)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    func delete(account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}

private struct SupabaseAuthResponse: Decodable {
    var accessToken: String
    var refreshToken: String?
    var expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

@MainActor
final class SupabaseCloudStore: ObservableObject {
    @Published var projectURL: String
    @Published var publishableKey: String
    @Published var email: String
    @Published var password = ""
    @Published private(set) var rows: [CloudUsageRow] = []
    @Published private(set) var sourceStatuses: [CloudSourceStatus] = []
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var hasLoaded = false
    var onSnapshot: ((UsageSnapshot) -> Void)?
    var onFailure: ((Error) -> Void)?
    var onReset: (() -> Void)?

    private var accessToken: String?
    private var refreshToken: String?
    private var expiresAt = Date.distantPast
    private var generation = UUID()
    private let defaults: UserDefaults
    private let passwordStorage: any CloudPasswordStorage
    private var credentialAccount: String?

    private var loginAccount: String {
        projectURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).lowercased() + "|" + email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    init(defaults: UserDefaults = .standard, passwordStorage: any CloudPasswordStorage = CloudKeychainPasswordStorage()) {
        self.passwordStorage = passwordStorage
        self.defaults = defaults
        LifecycleLogger.log("cloud_store_initialized authenticated=false")
        projectURL = defaults.string(forKey: "TokenStep.Supabase.URL") ?? ""
        publishableKey = defaults.string(forKey: "TokenStep.Supabase.PublishableKey") ?? ""
        email = defaults.string(forKey: "TokenStep.Supabase.Email") ?? ""
    }

    func restoreLogin() {
        guard !isAuthenticated, !isLoading, let saved = passwordStorage.read(account: loginAccount) else { return }
        password = saved
        signIn()
    }

    func signIn() {
        guard !isLoading else { return }
        LifecycleLogger.log("cloud_sign_in_started")
        persistPublicConfiguration()
        isLoading = true
        errorMessage = nil
        let currentGeneration = generation
        let attemptedAccount = loginAccount
        let attemptedPassword = password
        Task {
            defer { isLoading = false }
            do {
                let auth: SupabaseAuthResponse = try await request(
                    path: "/auth/v1/token?grant_type=password",
                    method: "POST",
                    body: ["email": email, "password": password],
                    authorization: nil
                )
                guard generation == currentGeneration else { return }
                accessToken = auth.accessToken
                refreshToken = auth.refreshToken
                expiresAt = Date().addingTimeInterval(Double(auth.expiresIn ?? 3600) - 60)
                credentialAccount = attemptedAccount
                if !passwordStorage.save(attemptedPassword, account: attemptedAccount) {
                    LifecycleLogger.log("cloud_password_save_failed")
                }
                password = ""
                isAuthenticated = true
                LifecycleLogger.log("cloud_sign_in_ok")
                try await loadRows()
            } catch {
                guard generation == currentGeneration else { return }
                isAuthenticated = accessToken != nil
                LifecycleLogger.log("cloud_sign_in_failed category=\(Self.safeError(error))")
                errorMessage = error.localizedDescription
                onFailure?(error)
            }
        }
    }

    func refresh() {
        guard !isLoading, accessToken != nil else { return }
        LifecycleLogger.log("cloud_refresh_started")
        isLoading = true
        errorMessage = nil
        let currentGeneration = generation
        Task {
            defer { isLoading = false }
            do {
                if Date() >= expiresAt, let refreshToken {
                    let auth: SupabaseAuthResponse = try await request(path: "/auth/v1/token?grant_type=refresh_token",
                        method: "POST", body: ["refresh_token": refreshToken], authorization: nil)
                    guard generation == currentGeneration else { return }
                    accessToken = auth.accessToken
                    self.refreshToken = auth.refreshToken
                    expiresAt = Date().addingTimeInterval(Double(auth.expiresIn ?? 3600) - 60)
                }
                try await loadRows()
            } catch {
                guard generation == currentGeneration else { return }
                errorMessage = error.localizedDescription
                LifecycleLogger.log("cloud_refresh_failed category=\(Self.safeError(error))")
                onFailure?(error)
            }
        }
    }

    func signOut() {
        LifecycleLogger.log("cloud_signed_out")
        passwordStorage.delete(account: credentialAccount ?? loginAccount)
        credentialAccount = nil
        generation = UUID()
        accessToken = nil
        refreshToken = nil
        password = ""
        rows = []
        sourceStatuses = []
        isAuthenticated = false
        hasLoaded = false
        onReset?()
    }

    private func loadRows() async throws {
        guard let accessToken else { throw CloudError.notAuthenticated }
        let currentGeneration = generation
        let started = Date()
        LifecycleLogger.log("cloud_read_started")
        var result: [CloudUsageRow] = []
        var offset = 0
        while true {
            let page: [CloudUsageRow] = try await request(
                path: "/rest/v1/usage_dashboard?select=*&order=local_date.desc,device_id,agent_key,model,project_key&limit=1000&offset=\(offset)",
                method: "GET", body: Optional<[String: String]>.none, authorization: accessToken
            )
            if page.isEmpty { break }
            result.append(contentsOf: page)
            offset += page.count
        }
        var statuses: [CloudSourceStatus] = []
        offset = 0
        while true {
            let page: [CloudSourceStatus] = try await request(
                path: "/rest/v1/source_sync_status?select=device_id,agent_key,state,files,records,last_succeeded_at&order=device_id,agent_key&limit=1000&offset=\(offset)",
                method: "GET", body: Optional<[String: String]>.none, authorization: accessToken)
            if page.isEmpty { break }
            statuses.append(contentsOf: page)
            offset += page.count
        }
        guard generation == currentGeneration else { return }
        rows = result
        sourceStatuses = statuses
        hasLoaded = true
        onSnapshot?(CloudSnapshotAdapter.snapshot(rows: result, statuses: statuses))
        LifecycleLogger.log("cloud_snapshot_applied rows=\(result.count) total_tokens=\(result.reduce(0) { $0 + $1.totalTokens }) devices=\(Set(result.map(\.deviceID)).count) sources=\(statuses.count) elapsed_ms=\(Int(Date().timeIntervalSince(started) * 1000))")
        let antigravity = result.filter { $0.agentKey.lowercased() == "antigravity" }
        let date = DateFormatter.tokenStepDay.string(from: Date())
        let today = antigravity.filter { $0.localDate == date }
        let latestDate = String((antigravity.map(\.localDate).max() ?? "none").filter { $0.isNumber || $0 == "-" }.prefix(10))
        LifecycleLogger.log("cloud_antigravity_applied rows=\(antigravity.count) today_rows=\(today.count) today_tokens=\(today.reduce(0) { $0 + $1.totalTokens }) latest_date=\(latestDate)")
    }

    private func persistPublicConfiguration() {
        defaults.set(projectURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "TokenStep.Supabase.URL")
        defaults.set(publishableKey.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "TokenStep.Supabase.PublishableKey")
        defaults.set(email.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "TokenStep.Supabase.Email")
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body?,
        authorization: String?
    ) async throws -> Response {
        let base = projectURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: base + path), url.scheme == "https" else { throw CloudError.invalidURL }
        let key = publishableKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw CloudError.missingPublishableKey }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let authorization {
            request.setValue("Bearer \(authorization)", forHTTPHeaderField: "Authorization")
        }
        if let body { request.httpBody = try JSONEncoder().encode(body) }
        let endpoint = String(path.split(separator: "?").first ?? "unknown")
        let started = Date()
        LifecycleLogger.log("cloud_http_started endpoint=\(endpoint)")
        let (data, response) = try await URLSession.shared.data(for: request)
        let requestID = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "sb-request-id").flatMap(UUID.init(uuidString:))?.uuidString ?? "none"
        LifecycleLogger.log("cloud_http endpoint=\(endpoint) status=\((response as? HTTPURLResponse)?.statusCode ?? 0) bytes=\(data.count) request_id=\(requestID) elapsed_ms=\(Int(Date().timeIntervalSince(started) * 1000))")
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw CloudError.requestRejected
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private static func safeError(_ error: Error) -> String {
        if let network = error as? URLError { return "network_\(network.code.rawValue)" }
        if error is DecodingError { return "decoding" }
        if error is CloudError { return "cloud_request" }
        return "unknown"
    }
}

private enum CloudError: LocalizedError {
    case invalidURL
    case missingPublishableKey
    case notAuthenticated
    case requestRejected

    var errorDescription: String? {
        switch self {
        case .invalidURL: return L("Supabase URL 无效，必须使用 HTTPS")
        case .missingPublishableKey: return L("缺少 Supabase Publishable Key")
        case .notAuthenticated: return L("请先登录")
        case .requestRejected: return L("Supabase 请求被拒绝，请检查账号、RLS 和部署状态")
        }
    }
}
