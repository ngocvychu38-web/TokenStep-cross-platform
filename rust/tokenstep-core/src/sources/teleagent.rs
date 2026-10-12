use std::path::PathBuf;

use chrono::{DateTime, FixedOffset, Utc};
use rusqlite::{Connection, OpenFlags};

use crate::{PlatformPaths, SourceAdapter, SourceDiagnostic, SourceState, TokenCounts, UsageFact};

use super::support::{project_key, project_name};

pub struct TeleAgentSource {
    paths: PlatformPaths,
}

impl TeleAgentSource {
    pub fn new(paths: PlatformPaths) -> Self {
        Self { paths }
    }
}

impl SourceAdapter for TeleAgentSource {
    fn key(&self) -> &'static str {
        "teleagent"
    }

    fn collect(&self) -> (Vec<UsageFact>, SourceDiagnostic) {
        let database = self
            .paths
            .teleagent_databases()
            .into_iter()
            .find(|path| path.exists());
        let Some(database) = database else {
            return (
                Vec::new(),
                diagnostic(self.key(), SourceState::Missing, 0, 0, None),
            );
        };
        match query_database(&database) {
            Ok(facts) => {
                let state = if facts.is_empty() {
                    SourceState::MissingValidRows
                } else {
                    SourceState::Ok
                };
                let records = facts.len() as u64;
                (facts, diagnostic(self.key(), state, 1, records, None))
            }
            Err(code) => (
                Vec::new(),
                diagnostic(self.key(), SourceState::QueryFailed, 1, 0, Some(code)),
            ),
        }
    }
}

pub struct OpenCodeSource {
    paths: PlatformPaths,
}

impl OpenCodeSource {
    pub fn new(paths: PlatformPaths) -> Self {
        Self { paths }
    }
}

impl SourceAdapter for OpenCodeSource {
    fn key(&self) -> &'static str {
        "opencode"
    }

    fn collect(&self) -> (Vec<UsageFact>, SourceDiagnostic) {
        let Some(database) = self
            .paths
            .opencode_databases()
            .into_iter()
            .find(|path| path.exists())
        else {
            return (
                vec![],
                diagnostic(self.key(), SourceState::Missing, 0, 0, None),
            );
        };
        match query_database(&database) {
            Ok(mut facts) => {
                for fact in &mut facts {
                    fact.agent_key = "opencode".into();
                    fact.agent_name = "OpenCode".into();
                    fact.source_event_id =
                        fact.source_event_id.replacen("teleagent:", "opencode:", 1);
                    if fact.model == "teleagent-unknown" {
                        fact.model = "opencode-unknown".into();
                    }
                }
                let state = if facts.is_empty() {
                    SourceState::MissingValidRows
                } else {
                    SourceState::Ok
                };
                let records = facts.len() as u64;
                (facts, diagnostic(self.key(), state, 1, records, None))
            }
            Err(error) => (
                vec![],
                diagnostic(self.key(), SourceState::QueryFailed, 1, 0, Some(error)),
            ),
        }
    }
}

fn diagnostic(
    key: &str,
    state: SourceState,
    files: u64,
    records: u64,
    error: Option<&str>,
) -> SourceDiagnostic {
    SourceDiagnostic {
        agent_key: key.into(),
        state,
        files,
        records,
        safe_error: error.map(ToOwned::to_owned),
    }
}

fn query_database(path: &PathBuf) -> Result<Vec<UsageFact>, &'static str> {
    let connection = Connection::open_with_flags(
        path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )
    .map_err(|_| "database_open_failed")?;
    let sql = r#"
        select message.id,
               message.time_created,
               coalesce(json_extract(message.data, '$.modelID'), 'teleagent-unknown'),
               coalesce(json_extract(message.data, '$.tokens.input'), 0),
               coalesce(json_extract(message.data, '$.tokens.output'), 0),
               coalesce(json_extract(message.data, '$.tokens.reasoning'), 0),
               coalesce(json_extract(message.data, '$.tokens.cache.read'), 0),
               coalesce(json_extract(message.data, '$.tokens.cache.write'), 0),
               coalesce(json_extract(message.data, '$.tokens.total'), 0),
               coalesce(nullif(session.directory, ''), json_extract(message.data, '$.path.cwd'))
        from message
        left join session on session.id = message.session_id
        where json_extract(message.data, '$.role') = 'assistant'
    "#;
    let mut statement = connection.prepare(sql).map_err(|_| "schema_mismatch")?;
    let rows = statement
        .query_map([], |row| {
            let created: i64 = row.get(1)?;
            let seconds = if created > 10_000_000_000 {
                created / 1000
            } else {
                created
            };
            let timestamp = DateTime::<Utc>::from_timestamp(seconds, 0).unwrap_or_default();
            let path: Option<String> = row.get(9)?;
            let input: u64 = row.get::<_, i64>(3)?.max(0) as u64;
            let output: u64 = row.get::<_, i64>(4)?.max(0) as u64;
            let reasoning: u64 = row.get::<_, i64>(5)?.max(0) as u64;
            let cache_read: u64 = row.get::<_, i64>(6)?.max(0) as u64;
            let cache_write: u64 = row.get::<_, i64>(7)?.max(0) as u64;
            let explicit_total: u64 = row.get::<_, i64>(8)?.max(0) as u64;
            let mut tokens = TokenCounts::from_components(input, output, cache_read, cache_write);
            tokens.reasoning_tokens = reasoning;
            if explicit_total > 0 {
                tokens.total_tokens = explicit_total;
            }
            Ok(UsageFact {
                occurred_at: timestamp.to_rfc3339(),
                local_date: timestamp
                    .with_timezone(&FixedOffset::east_opt(8 * 3600).unwrap())
                    .format("%Y-%m-%d")
                    .to_string(),
                agent_key: "teleagent".into(),
                agent_name: "TeleAgent".into(),
                model: row.get(2)?,
                project_key: project_key(path.as_deref()),
                project_name: project_name(path.as_deref()),
                source_event_id: format!("teleagent:{}", row.get::<_, String>(0)?),
                tokens,
            })
        })
        .map_err(|_| "query_failed")?;
    let facts: Vec<_> = rows
        .collect::<Result<_, _>>()
        .map_err(|_| "invalid_usage_row")?;
    Ok(facts
        .into_iter()
        .filter(|fact| !fact.tokens.is_empty())
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::NamedTempFile;

    #[test]
    fn reads_only_assistant_usage_and_prefers_session_directory() {
        let file = NamedTempFile::new().unwrap();
        let db = Connection::open(file.path()).unwrap();
        db.execute_batch(r#"
            create table session (id text primary key, directory text);
            create table message (id text primary key, session_id text, time_created integer, data text);
            insert into session values ('s1', '/work/tokenhub');
            insert into message values ('m1', 's1', 1760000000000,
              '{"role":"assistant","modelID":"gpt-5","tokens":{"input":10,"output":4,"reasoning":2,"cache":{"read":3,"write":1},"total":18},"path":{"cwd":"/wrong/project"}}');
            insert into message values ('m2', 's1', 1760000000000,
              '{"role":"user","tokens":{"input":999,"output":999}}');
        "#).unwrap();
        drop(db);
        let facts = query_database(&file.path().to_path_buf()).unwrap();
        assert_eq!(facts.len(), 1);
        assert_eq!(facts[0].project_name, "tokenhub");
        assert_eq!(facts[0].tokens.total_tokens, 18);
        assert_eq!(facts[0].tokens.reasoning_tokens, 2);
    }
}
