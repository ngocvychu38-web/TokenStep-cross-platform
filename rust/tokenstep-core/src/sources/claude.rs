use std::{
    collections::BTreeMap,
    fs::File,
    io::{BufRead, BufReader},
};

use serde_json::Value;

use crate::{PlatformPaths, SourceAdapter, SourceDiagnostic, SourceState, UsageFact};

use super::support::{jsonl_files, local_date, project_key, project_name, token_counts};

pub struct ClaudeCodeSource {
    paths: PlatformPaths,
}

impl ClaudeCodeSource {
    pub fn new(paths: PlatformPaths) -> Self {
        Self { paths }
    }
}

impl SourceAdapter for ClaudeCodeSource {
    fn key(&self) -> &'static str {
        "claude_code"
    }

    fn collect(&self) -> (Vec<UsageFact>, SourceDiagnostic) {
        let files: Vec<_> = self
            .paths
            .claude_projects()
            .iter()
            .flat_map(|root| jsonl_files(root))
            .collect();
        let mut facts_by_id: BTreeMap<String, UsageFact> = BTreeMap::new();
        let mut parse_errors = 0u64;

        for path in &files {
            let Ok(file) = File::open(path) else {
                parse_errors += 1;
                continue;
            };
            for (line_number, line) in BufReader::new(file).lines().enumerate() {
                let Ok(line) = line else {
                    parse_errors += 1;
                    continue;
                };
                if !line.contains("usage") {
                    continue;
                }
                let Ok(row) = serde_json::from_str::<Value>(&line) else {
                    parse_errors += 1;
                    continue;
                };
                if row.get("type").and_then(Value::as_str) != Some("assistant") {
                    continue;
                }
                let Some(message) = row.get("message") else {
                    continue;
                };
                let tokens = token_counts(message.get("usage"));
                if tokens.is_empty() {
                    continue;
                }
                let Some(timestamp) = row.get("timestamp").and_then(Value::as_str) else {
                    continue;
                };
                let Some(day) = local_date(timestamp) else {
                    continue;
                };
                let message_id = message
                    .get("id")
                    .and_then(Value::as_str)
                    .map(ToOwned::to_owned)
                    .unwrap_or_else(|| format!("{}:{}", path.display(), line_number));
                let cwd = row.get("cwd").and_then(Value::as_str);
                let fact = UsageFact {
                    occurred_at: timestamp.to_owned(),
                    local_date: day,
                    agent_key: self.key().into(),
                    agent_name: "Claude Code".into(),
                    model: message
                        .get("model")
                        .and_then(Value::as_str)
                        .unwrap_or("unknown")
                        .into(),
                    project_key: project_key(cwd),
                    project_name: project_name(cwd),
                    source_event_id: format!("claude:{message_id}"),
                    tokens,
                };
                match facts_by_id.get(&message_id) {
                    Some(existing) if existing.tokens.total_tokens >= fact.tokens.total_tokens => {}
                    _ => {
                        facts_by_id.insert(message_id, fact);
                    }
                }
            }
        }

        let facts: Vec<_> = facts_by_id.into_values().collect();
        let state = if parse_errors > 0 {
            SourceState::ParseFailed
        } else if !facts.is_empty() {
            SourceState::Ok
        } else if files.is_empty() {
            SourceState::Missing
        } else {
            SourceState::MissingValidRows
        };
        let diagnostic = SourceDiagnostic {
            agent_key: self.key().into(),
            state,
            files: files.len() as u64,
            records: facts.len() as u64,
            safe_error: (parse_errors > 0).then(|| "one_or_more_files_could_not_be_parsed".into()),
        };
        (facts, diagnostic)
    }
}
