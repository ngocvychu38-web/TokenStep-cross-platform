use std::{collections::BTreeMap, fs, path::PathBuf};

use chrono::{DateTime, Utc};
use serde_json::Value;

use super::support::{local_date, project_key, project_name, token_counts, unsigned};
use crate::{PlatformPaths, SourceAdapter, SourceDiagnostic, SourceState, TokenCounts, UsageFact};

pub struct JsonAgentSource {
    paths: PlatformPaths,
    key: &'static str,
    name: &'static str,
    roots: &'static [&'static str],
}

impl JsonAgentSource {
    pub fn all(paths: &PlatformPaths) -> Vec<Box<dyn SourceAdapter>> {
        [
            ("gemini_cli", "Gemini CLI", &[".gemini/tmp"][..]),
            (
                "qwen_code",
                "Qwen Code",
                &[".qwen/tmp", ".qwen/projects"][..],
            ),
            ("kimi_code", "Kimi Code", &[".kimi-code/sessions"][..]),
            ("grok_build", "Grok Build", &[".grok/sessions"][..]),
            ("amp", "Amp", &[".local/share/amp/threads"][..]),
            ("droid", "Droid", &[".factory/sessions"][..]),
            (
                "workbuddy",
                "WorkBuddy",
                &[".workbuddy-ai/projects", ".workbuddy/projects"][..],
            ),
        ]
        .into_iter()
        .map(|(key, name, roots)| {
            Box::new(Self {
                paths: paths.clone(),
                key,
                name,
                roots,
            }) as Box<dyn SourceAdapter>
        })
        .collect()
    }

    fn fact(
        &self,
        row: &Value,
        file: &std::path::Path,
        index: usize,
        session: &str,
    ) -> Option<UsageFact> {
        let usage = match self.key {
            "gemini_cli" => row.get("tokens").or_else(|| row.get("usageMetadata")),
            "qwen_code" => row.get("usageMetadata"),
            "kimi_code" => {
                let kind = row.pointer("/message/type")?.as_str()?.to_lowercase();
                if !kind.contains("usagerecord") {
                    return None;
                }
                row.pointer("/message/payload/usage")
                    .or_else(|| row.pointer("/message/payload"))
            }
            "grok_build" => {
                if row.pointer("/params/update/sessionUpdate")?.as_str()? != "turn_completed" {
                    return None;
                }
                row.pointer("/params/update/usage")
            }
            _ => row
                .get("usage")
                .or_else(|| row.get("rawUsage"))
                .or_else(|| row.pointer("/payload/usage"))
                .or_else(|| row.pointer("/update/usage")),
        }?;
        let tokens = if matches!(self.key, "gemini_cli" | "qwen_code") {
            gemini_counts(usage)
        } else if self.key == "grok_build" {
            let cached = unsigned(usage.get("cachedReadTokens"));
            let mut counts = TokenCounts::from_components(
                unsigned(usage.get("inputTokens")).saturating_sub(cached),
                unsigned(usage.get("outputTokens")),
                cached,
                0,
            );
            counts.reasoning_tokens = unsigned(usage.get("reasoningTokens"));
            let total = unsigned(usage.get("totalTokens"));
            if total > 0 {
                counts.total_tokens = total;
            }
            counts
        } else {
            token_counts(Some(usage))
        };
        if tokens.is_empty() {
            return None;
        }
        let raw_time = row.get("timestamp")?;
        let timestamp = if let Some(text) = raw_time.as_str() {
            text.to_owned()
        } else {
            let epoch = raw_time.as_f64()?;
            let seconds = if epoch > 10_000_000_000.0 {
                epoch / 1000.0
            } else {
                epoch
            };
            DateTime::<Utc>::from_timestamp(seconds as i64, 0)?.to_rfc3339()
        };
        let day = local_date(&timestamp)?;
        let cwd = row
            .get("cwd")
            .or_else(|| row.pointer("/message/payload/cwd"))
            .and_then(Value::as_str);
        let id = row
            .get("id")
            .or_else(|| row.pointer("/params/update/prompt_id"))
            .and_then(Value::as_str)
            .map(ToOwned::to_owned)
            .unwrap_or_else(|| format!("{}:{index}", file.display()));
        let model = row
            .get("model")
            .or_else(|| usage.get("model"))
            .or_else(|| row.pointer("/message/payload/model"))
            .and_then(Value::as_str)
            .unwrap_or("unknown");
        Some(UsageFact {
            occurred_at: timestamp,
            local_date: day,
            agent_key: self.key.into(),
            agent_name: self.name.into(),
            model: model.into(),
            project_key: project_key(cwd),
            project_name: project_name(cwd),
            source_event_id: format!("{}:{session}:{id}", self.key),
            tokens,
        })
    }
}

impl SourceAdapter for JsonAgentSource {
    fn key(&self) -> &'static str {
        self.key
    }

    fn collect(&self) -> (Vec<UsageFact>, SourceDiagnostic) {
        let mut files: Vec<PathBuf> = self
            .roots
            .iter()
            .flat_map(|root| {
                walkdir::WalkDir::new(self.paths.home().join(root))
                    .into_iter()
                    .filter_map(Result::ok)
                    .filter(|entry| {
                        entry.file_type().is_file()
                            && entry
                                .path()
                                .extension()
                                .is_some_and(|ext| ext == "jsonl" || ext == "json")
                    })
                    .map(|entry| entry.into_path())
            })
            .collect();
        files.sort();
        files.dedup();
        let mut facts = BTreeMap::new();
        let mut failures = 0;
        for file in &files {
            if self.key == "gemini_cli"
                && !file
                    .file_name()
                    .is_some_and(|name| name.to_string_lossy().starts_with("session-"))
            {
                continue;
            }
            if self.key == "kimi_code" && file.file_name().is_none_or(|name| name != "wire.jsonl") {
                continue;
            }
            if self.key == "grok_build"
                && file.file_name().is_none_or(|name| name != "updates.jsonl")
            {
                continue;
            }
            let Ok(content) = fs::read_to_string(file) else {
                failures += 1;
                continue;
            };
            let session = file
                .file_stem()
                .and_then(|name| name.to_str())
                .unwrap_or("unknown");
            if file.extension().is_some_and(|ext| ext == "json") {
                let Ok(doc) = serde_json::from_str::<Value>(&content) else {
                    failures += 1;
                    continue;
                };
                let session = doc
                    .get("sessionId")
                    .and_then(Value::as_str)
                    .unwrap_or(session);
                if let Some(messages) = doc.get("messages").and_then(Value::as_array) {
                    for (index, row) in messages.iter().enumerate() {
                        if let Some(fact) = self.fact(row, file, index, session) {
                            facts.insert(fact.source_event_id.clone(), fact);
                        }
                    }
                }
            } else {
                for (index, line) in content.lines().enumerate() {
                    let Ok(row) = serde_json::from_str::<Value>(line) else {
                        continue;
                    };
                    if let Some(fact) = self.fact(&row, file, index, session) {
                        facts.insert(fact.source_event_id.clone(), fact);
                    }
                }
            }
        }
        let state = if failures > 0 {
            SourceState::ParseFailed
        } else if !facts.is_empty() {
            SourceState::Ok
        } else if files.is_empty() {
            SourceState::Missing
        } else {
            SourceState::MissingValidRows
        };
        let diagnostic = SourceDiagnostic {
            agent_key: self.key.into(),
            state,
            files: files.len() as u64,
            records: facts.len() as u64,
            safe_error: (failures > 0).then(|| "file_read_failed".into()),
        };
        (facts.into_values().collect(), diagnostic)
    }
}

fn gemini_counts(usage: &Value) -> TokenCounts {
    let input = unsigned(usage.get("promptTokenCount").or_else(|| usage.get("input")));
    let cached = unsigned(
        usage
            .get("cachedContentTokenCount")
            .or_else(|| usage.get("cached")),
    );
    let output = unsigned(
        usage
            .get("candidatesTokenCount")
            .or_else(|| usage.get("output")),
    );
    let thoughts = unsigned(
        usage
            .get("thoughtsTokenCount")
            .or_else(|| usage.get("thoughts")),
    );
    let mut counts = TokenCounts::from_components(input.saturating_sub(cached), output, cached, 0);
    counts.reasoning_tokens = thoughts;
    counts.total_tokens = unsigned(usage.get("totalTokenCount").or_else(|| usage.get("total")));
    if counts.total_tokens == 0 {
        counts.total_tokens = input.saturating_add(output).saturating_add(thoughts);
    }
    counts
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn gemini_explicit_total_and_cached_prompt_are_preserved() {
        let usage = serde_json::json!({"promptTokenCount":100,"cachedContentTokenCount":60,"candidatesTokenCount":20,"thoughtsTokenCount":5,"totalTokenCount":125});
        let counts = gemini_counts(&usage);
        assert_eq!(counts.input_tokens, 40);
        assert_eq!(counts.total_tokens, 125);
    }
}
