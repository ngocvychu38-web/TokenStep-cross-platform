use std::{
    collections::BTreeMap,
    fs::File,
    io::{BufRead, BufReader},
    path::Path,
};

use serde_json::Value;

use crate::{PlatformPaths, SourceAdapter, SourceDiagnostic, SourceState, TokenCounts, UsageFact};

use super::support::{jsonl_files, local_date, project_key, project_name, token_counts};

pub struct CodexSource {
    paths: PlatformPaths,
}

impl CodexSource {
    pub fn new(paths: PlatformPaths) -> Self {
        Self { paths }
    }
}

#[derive(Default)]
struct SessionState {
    session_id: String,
    model: String,
    cwd: Option<String>,
    previous: TokenCounts,
}

impl SourceAdapter for CodexSource {
    fn key(&self) -> &'static str {
        "codex"
    }

    fn collect(&self) -> (Vec<UsageFact>, SourceDiagnostic) {
        let files: Vec<_> = self
            .paths
            .codex_sessions()
            .iter()
            .flat_map(|root| jsonl_files(root))
            .collect();
        let mut facts = Vec::new();
        let mut parse_errors = 0u64;
        for path in &files {
            match collect_file(path) {
                Ok(mut rows) => facts.append(&mut rows),
                Err(()) => parse_errors += 1,
            }
        }
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

fn collect_file(path: &Path) -> Result<Vec<UsageFact>, ()> {
    let file = File::open(path).map_err(|_| ())?;
    let mut session = SessionState {
        model: "unknown".into(),
        session_id: path
            .file_stem()
            .and_then(|v| v.to_str())
            .unwrap_or("unknown")
            .into(),
        ..Default::default()
    };
    let mut facts = Vec::new();
    let mut seen = BTreeMap::<String, ()>::new();

    for (line_number, line) in BufReader::new(file).lines().enumerate() {
        let line = line.map_err(|_| ())?;
        if !line.contains("session_meta")
            && !line.contains("turn_context")
            && !line.contains("token_count")
        {
            continue;
        }
        let Ok(row) = serde_json::from_str::<Value>(&line) else {
            continue;
        };
        let row_type = row.get("type").and_then(Value::as_str);
        let payload = row.get("payload");
        if row_type == Some("session_meta") {
            if let Some(id) = payload.and_then(|v| v.get("id")).and_then(Value::as_str) {
                session.session_id = id.into();
            }
            session.cwd = payload
                .and_then(|v| v.get("cwd"))
                .and_then(Value::as_str)
                .map(ToOwned::to_owned);
            continue;
        }
        if row_type == Some("turn_context") {
            if let Some(model) = payload.and_then(|v| v.get("model")).and_then(Value::as_str) {
                session.model = model.into();
            }
            continue;
        }
        if row_type != Some("event_msg")
            || payload.and_then(|v| v.get("type")).and_then(Value::as_str) != Some("token_count")
        {
            continue;
        }
        let Some(info) = payload.and_then(|v| v.get("info")) else {
            continue;
        };
        let timestamp = row.get("timestamp").and_then(Value::as_str).unwrap_or("");
        let Some(day) = local_date(timestamp) else {
            continue;
        };
        let cumulative = codex_counts(info.get("total_token_usage"));
        let last = codex_counts(info.get("last_token_usage"));
        let delta = if !cumulative.is_empty() {
            delta_or_reset(&cumulative, &session.previous)
        } else {
            last
        };
        if !cumulative.is_empty() {
            session.previous = cumulative;
        }
        if delta.is_empty() {
            continue;
        }
        let identity = format!("codex:{}:{}", session.session_id, line_number);
        if seen.insert(identity.clone(), ()).is_some() {
            continue;
        }
        facts.push(UsageFact {
            occurred_at: timestamp.into(),
            local_date: day,
            agent_key: "codex".into(),
            agent_name: "Codex".into(),
            model: session.model.clone(),
            project_key: project_key(session.cwd.as_deref()),
            project_name: project_name(session.cwd.as_deref()),
            source_event_id: identity,
            tokens: delta,
        });
    }
    Ok(facts)
}

fn codex_counts(value: Option<&Value>) -> TokenCounts {
    let mut counts = token_counts(value);
    // Codex input already contains cached reads; store exclusive input in the cloud contract.
    counts.input_tokens = counts.input_tokens.saturating_sub(counts.cache_read_tokens);
    if value
        .and_then(|v| v.get("total_tokens").or_else(|| v.get("total")))
        .is_none()
    {
        counts.total_tokens = counts
            .input_tokens
            .saturating_add(counts.cache_read_tokens)
            .saturating_add(counts.output_tokens);
    }
    counts.reasoning_tokens = value
        .and_then(|v| v.get("reasoning_output_tokens"))
        .and_then(Value::as_u64)
        .unwrap_or(counts.reasoning_tokens);
    counts
}

fn delta_or_reset(current: &TokenCounts, previous: &TokenCounts) -> TokenCounts {
    if current.total_tokens < previous.total_tokens {
        return current.clone();
    }
    TokenCounts {
        input_tokens: current.input_tokens.saturating_sub(previous.input_tokens),
        output_tokens: current.output_tokens.saturating_sub(previous.output_tokens),
        cache_read_tokens: current
            .cache_read_tokens
            .saturating_sub(previous.cache_read_tokens),
        cache_write_tokens: current
            .cache_write_tokens
            .saturating_sub(previous.cache_write_tokens),
        reasoning_tokens: current
            .reasoning_tokens
            .saturating_sub(previous.reasoning_tokens),
        total_tokens: current.total_tokens.saturating_sub(previous.total_tokens),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cached_input_and_reasoning_are_not_counted_twice() {
        let value = serde_json::json!({"input_tokens":100,"cached_input_tokens":60,"output_tokens":20,"reasoning_output_tokens":10});
        let counts = codex_counts(Some(&value));
        assert_eq!(counts.input_tokens, 40);
        assert_eq!(counts.total_tokens, 120);
        assert_eq!(counts.reasoning_tokens, 10);
    }

    #[test]
    fn cumulative_counters_become_deltas_and_reset_safely() {
        let first = TokenCounts::from_components(100, 20, 5, 0);
        let second = TokenCounts::from_components(150, 30, 10, 0);
        assert_eq!(delta_or_reset(&second, &first).total_tokens, 65);
        assert_eq!(delta_or_reset(&first, &second).total_tokens, 125);
    }
}
