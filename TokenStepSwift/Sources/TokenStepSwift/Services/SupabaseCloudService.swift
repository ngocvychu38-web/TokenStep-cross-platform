import Foundation


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
    private let defaults = UserDefaults.standard

    init() {
        projectURL = defaults.string(forKey: "TokenStep.Supabase.URL") ?? ""
        publishableKey = defaults.string(forKey: "TokenStep.Supabase.PublishableKey") ?? ""
        email = defaults.string(forKey: "TokenStep.Supabase.Email") ?? ""
    }

    func signIn() {
        guard !isLoading else { return }
        persistPublicConfiguration()
        isLoading = true
        errorMessage = nil
        let currentGeneration = generation
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
                password = ""
                isAuthenticated = true
                try await loadRows()
            } catch {
                guard generation == currentGeneration else { return }
                isAuthenticated = accessToken != nil
                errorMessage = error.localizedDescription
                onFailure?(error)
            }
        }
    }

    func refresh() {
        guard !isLoading, accessToken != nil else { return }
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
                onFailure?(error)
            }
        }
    }

    func signOut() {
        generation = UUID()
        accessToken = nil
        refreshToken = nil
        password = ""
        rows = []
        isAuthenticated = false
        hasLoaded = false
        onReset?()
    }

    private func loadRows() async throws {
        guard let accessToken else { throw CloudError.notAuthenticated }
        let currentGeneration = generation
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
                path: "/rest/v1/source_sync_status?select=agent_key,state,files,records,last_succeeded_at&order=device_id,agent_key&limit=1000&offset=\(offset)",
                method: "GET", body: Optional<[String: String]>.none, authorization: accessToken)
            if page.isEmpty { break }
            statuses.append(contentsOf: page)
            offset += page.count
        }
        guard generation == currentGeneration else { return }
        rows = result
        hasLoaded = true
        onSnapshot?(CloudSnapshotAdapter.snapshot(rows: result, statuses: statuses))
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
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw CloudError.requestRejected
        }
        return try JSONDecoder().decode(Response.self, from: data)
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
