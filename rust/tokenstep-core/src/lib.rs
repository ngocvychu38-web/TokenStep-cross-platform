mod aggregate;
mod collector;
mod model;
mod paths;
mod sources;

pub use aggregate::aggregate_facts;
pub use collector::{Collector, SourceAdapter};
pub use model::{
    CollectionSnapshot, DeviceDescriptor, SourceDiagnostic, SourceState, TokenCounts,
    UsageBucketV1, UsageFact,
};
pub use paths::PlatformPaths;
pub use sources::{ClaudeCodeSource, CodexSource, OpenCodeSource, TeleAgentSource};

pub const CONTRACT_VERSION: u32 = 1;
pub use sources::JsonAgentSource;
