import Foundation

struct CloudUsageRow: Codable, Identifiable, Equatable {
    var workspaceID: UUID
    var localDate: String
    var deviceID: UUID
    var deviceName: String
    var osFamily: String
    var osVersion: String
    var architecture: String
    var agentKey: String
    var agentName: String
    var projectKey: String
    var projectName: String
    var model: String
    var inputTokens: Int
    var outputTokens: Int
    var cacheReadTokens: Int
    var cacheWriteTokens: Int
    var reasoningTokens: Int
    var totalTokens: Int
    var recordCount: Int
    var lastSeenAt: String?

    var id: String {
        "\(deviceID.uuidString):\(localDate):\(agentKey):\(model):\(projectKey)"
    }

    enum CodingKeys: String, CodingKey {
        case workspaceID = "workspace_id"
        case localDate = "local_date"
        case deviceID = "device_id"
        case deviceName = "device_name"
        case osFamily = "os_family"
        case osVersion = "os_version"
        case architecture
        case agentKey = "agent_key"
        case agentName = "agent_name"
        case projectKey = "project_key"
        case projectName = "project_name"
        case model
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadTokens = "cache_read_tokens"
        case cacheWriteTokens = "cache_write_tokens"
        case reasoningTokens = "reasoning_tokens"
        case totalTokens = "total_tokens"
        case recordCount = "record_count"
        case lastSeenAt = "last_seen_at"
    }
}

private struct SupabaseAuthResponse: Decodable {
    var accessToken: String
    var refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
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

    private var accessToken: String?
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
        Task {
            defer { isLoading = false }
            do {
                let auth: SupabaseAuthResponse = try await request(
                    path: "/auth/v1/token?grant_type=password",
                    method: "POST",
                    body: ["email": email, "password": password],
                    authorization: nil
                )
                accessToken = auth.accessToken
                password = ""
                isAuthenticated = true
                try await loadRows()
            } catch {
                isAuthenticated = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func refresh() {
        guard !isLoading, accessToken != nil else { return }
        isLoading = true
        errorMessage = nil
        Task {
            defer { isLoading = false }
            do {
                try await loadRows()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func signOut() {
        accessToken = nil
        password = ""
        rows = []
        isAuthenticated = false
    }

    private func loadRows() async throws {
        guard let accessToken else { throw CloudError.notAuthenticated }
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
        rows = result
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
