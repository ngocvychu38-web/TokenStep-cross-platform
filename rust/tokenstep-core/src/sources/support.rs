use std::path::Path;

use chrono::{DateTime, FixedOffset};
use serde_json::Value;
use sha2::{Digest, Sha256};

use crate::TokenCounts;

pub fn unsigned(value: Option<&Value>) -> u64 {
    value
        .and_then(|item| {
            item.as_u64()
                .or_else(|| item.as_i64().and_then(|v| u64::try_from(v).ok()))
        })
        .unwrap_or(0)
}

pub fn token_counts(value: Option<&Value>) -> TokenCounts {
    let Some(value) = value else {
        return TokenCounts::default();
    };
    let input = unsigned(
        value
            .get("input_tokens")
            .or_else(|| value.get("inputTokens"))
            .or_else(|| value.get("input")),
    );
    let output = unsigned(
        value
            .get("output_tokens")
            .or_else(|| value.get("outputTokens"))
            .or_else(|| value.get("output")),
    );
    let cache_read = unsigned(
        value
            .get("cached_input_tokens")
            .or_else(|| value.get("cache_read_input_tokens"))
            .or_else(|| value.get("cache_read_tokens"))
            .or_else(|| value.pointer("/cache/read")),
    );
    let cache_write = unsigned(
        value
            .get("cache_creation_input_tokens")
            .or_else(|| value.get("cache_write_tokens"))
            .or_else(|| value.pointer("/cache/write")),
    );
    let reasoning = unsigned(
        value
            .get("reasoning_tokens")
            .or_else(|| value.get("reasoningTokens")),
    );
    let explicit_total = unsigned(
        value
            .get("total_tokens")
            .or_else(|| value.get("totalTokens"))
            .or_else(|| value.get("total")),
    );
    let mut result = TokenCounts::from_components(input, output, cache_read, cache_write);
    result.reasoning_tokens = reasoning;
    if explicit_total > 0 {
        result.total_tokens = explicit_total;
    }
    result
}

pub fn local_date(timestamp: &str) -> Option<String> {
    DateTime::parse_from_rfc3339(timestamp).ok().map(|date| {
        date.with_timezone(&FixedOffset::east_opt(8 * 3600).unwrap())
            .format("%Y-%m-%d")
            .to_string()
    })
}

pub fn project_name(path: Option<&str>) -> String {
    path.and_then(|value| {
        value
            .trim_end_matches(['/', '\\'])
            .rsplit(['/', '\\'])
            .next()
    })
    .filter(|value| !value.is_empty())
    .unwrap_or("Unnamed")
    .chars()
    .take(64)
    .collect()
}

pub fn project_key(path: Option<&str>) -> String {
    let canonical = path.unwrap_or("Unnamed").replace('\\', "/").to_lowercase();
    let digest = Sha256::digest(canonical.as_bytes());
    hex::encode(&digest[..16])
}

pub fn jsonl_files(root: &Path) -> Vec<std::path::PathBuf> {
    if !root.exists() {
        return Vec::new();
    }
    walkdir::WalkDir::new(root)
        .follow_links(false)
        .into_iter()
        .filter_map(Result::ok)
        .filter(|entry| {
            entry.file_type().is_file()
                && entry.path().extension().is_some_and(|ext| ext == "jsonl")
        })
        .map(|entry| entry.into_path())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shanghai_day_and_windows_project_are_platform_independent() {
        assert_eq!(
            local_date("2026-10-06T17:00:00Z").as_deref(),
            Some("2026-10-07")
        );
        assert_eq!(project_name(Some(r"C:\work\tokenhub")), "tokenhub");
    }
}
