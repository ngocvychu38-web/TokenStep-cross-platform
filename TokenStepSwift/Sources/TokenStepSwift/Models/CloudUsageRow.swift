import Foundation

struct CloudDeviceUsage: Identifiable {
    var id: UUID
    var name: String
    var osFamily: String
    var tokens: Int
    var agents: [CloudAgentUsage]
}

struct CloudAgentUsage: Identifiable {
    var id: String
    var name: String
    var tokens: Int?
}

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
    var hourlyUsage: [CloudHourUsage]?

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
        case hourlyUsage = "hourly_usage"
    }
}

struct CloudTokenCounts: Codable, Equatable {
    var input_tokens: Int
    var output_tokens: Int
    var cache_read_tokens: Int
    var cache_write_tokens: Int
    var reasoning_tokens: Int
    var total_tokens: Int
}

struct CloudHourUsage: Codable, Equatable {
    var hour: Int
    var tokens: CloudTokenCounts
    var record_count: Int
}

struct CloudSourceStatus: Decodable {
    var device_id: UUID? = nil
    var agent_key: String
    var state: String
    var files: Int
    var records: Int
    var last_succeeded_at: String?
}
