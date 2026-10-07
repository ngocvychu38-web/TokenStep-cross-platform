use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TokenCounts {
    pub input_tokens: u64,
    pub output_tokens: u64,
    pub cache_read_tokens: u64,
    pub cache_write_tokens: u64,
    pub reasoning_tokens: u64,
    pub total_tokens: u64,
}

impl TokenCounts {
    pub fn from_components(input: u64, output: u64, cache_read: u64, cache_write: u64) -> Self {
        Self {
            input_tokens: input,
            output_tokens: output,
            cache_read_tokens: cache_read,
            cache_write_tokens: cache_write,
            reasoning_tokens: 0,
            total_tokens: input
                .saturating_add(output)
                .saturating_add(cache_read)
                .saturating_add(cache_write),
        }
    }

    pub fn add_assign(&mut self, other: &Self) {
        self.input_tokens = self.input_tokens.saturating_add(other.input_tokens);
        self.output_tokens = self.output_tokens.saturating_add(other.output_tokens);
        self.cache_read_tokens = self
            .cache_read_tokens
            .saturating_add(other.cache_read_tokens);
        self.cache_write_tokens = self
            .cache_write_tokens
            .saturating_add(other.cache_write_tokens);
        self.reasoning_tokens = self.reasoning_tokens.saturating_add(other.reasoning_tokens);
        self.total_tokens = self.total_tokens.saturating_add(other.total_tokens);
    }

    pub fn is_empty(&self) -> bool {
        self.total_tokens == 0
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct UsageFact {
    pub occurred_at: String,
    pub local_date: String,
    pub agent_key: String,
    pub agent_name: String,
    pub model: String,
    pub project_key: String,
    pub project_name: String,
    pub source_event_id: String,
    pub tokens: TokenCounts,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct UsageBucketV1 {
    pub schema_version: u32,
    pub local_date: String,
    pub timezone: String,
    pub agent_key: String,
    pub agent_name: String,
    pub model: String,
    pub project_key: String,
    pub project_name: String,
    pub tokens: TokenCounts,
    pub record_count: u64,
    #[serde(default)]
    pub hourly_usage: Vec<HourlyUsage>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HourlyUsage {
    pub hour: u32,
    pub tokens: TokenCounts,
    pub record_count: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SourceState {
    Ok,
    Missing,
    MissingValidRows,
    QueryFailed,
    ParseFailed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourceDiagnostic {
    pub agent_key: String,
    pub state: SourceState,
    pub files: u64,
    pub records: u64,
    pub safe_error: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DeviceDescriptor {
    pub device_id: String,
    pub display_name: String,
    pub os_family: String,
    pub os_version: String,
    pub architecture: String,
    pub collector_version: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CollectionSnapshot {
    pub schema_version: u32,
    pub generated_at: String,
    pub timezone: String,
    pub device: DeviceDescriptor,
    pub buckets: Vec<UsageBucketV1>,
    pub sources: Vec<SourceDiagnostic>,
}
