//! Antigravity / Antigravity IDE（实验）：只读 `~/.gemini/antigravity/conversations/*.db`
//! 与 `~/.gemini/antigravity-ide/conversations/*.db`，两者存储结构相同，按产品分别统计。
//!
//! Antigravity 没有公开格式，字段编号来自对本机样本的结构探测（只看数值，不读正文）：
//! - `gen_metadata.data` 每行是一次模型调用：`1.4` 为用量（2 未命中缓存输入、5 缓存读取、
//!   3 输出合计），`1.19` 为模型名，`1.4.7` 为调用 ID，`1.20` 为键值标记，其中
//!   `last_step_index` 指向 `steps` 表的行。
//! - `steps.metadata` 的 `1.1` 为该步骤的 epoch 秒。
//!
//! 只读取 `gen_metadata.data`、`steps.metadata` 与摘要库的 `workspace_uris`；
//! `step_payload` 等对话内容列从不查询。任一关键字段缺失时跳过该行，不做猜测。

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use chrono::{DateTime, FixedOffset, Utc};
use rusqlite::{Connection, OpenFlags};

use crate::{PlatformPaths, SourceAdapter, SourceDiagnostic, SourceState, TokenCounts, UsageFact};

use super::support::{project_key, project_name};

pub struct AntigravitySource {
    root: PathBuf,
    key: &'static str,
    name: &'static str,
}

impl AntigravitySource {
    pub fn new(paths: PlatformPaths) -> Self {
        Self {
            root: paths.antigravity_root(),
            key: "antigravity",
            name: "Antigravity",
        }
    }

    pub fn ide(paths: PlatformPaths) -> Self {
        Self {
            root: paths.antigravity_ide_root(),
            key: "antigravity_ide",
            name: "Antigravity IDE",
        }
    }
}

impl SourceAdapter for AntigravitySource {
    fn key(&self) -> &'static str {
        self.key
    }

    fn collect(&self) -> (Vec<UsageFact>, SourceDiagnostic) {
        let root = &self.root;
        let databases = conversation_databases(&root.join("conversations"));
        if databases.is_empty() {
            return (
                vec![],
                diagnostic(self.key, SourceState::Missing, 0, 0, None),
            );
        }
        let workspaces = workspace_paths(&root.join("conversation_summaries.db"));
        let mut facts = Vec::new();
        let mut failed = 0u64;
        let mut skipped = 0u64;
        for database in &databases {
            let conversation_id = database
                .file_stem()
                .and_then(|stem| stem.to_str())
                .unwrap_or_default()
                .to_owned();
            let workspace = workspaces.get(&conversation_id).map(String::as_str);
            match query_conversation(self, database, &conversation_id, workspace) {
                Ok((mut rows, skipped_rows)) => {
                    facts.append(&mut rows);
                    skipped += skipped_rows;
                }
                Err(_) => failed += 1,
            }
        }
        let files = databases.len() as u64;
        let records = facts.len() as u64;
        let state = if !facts.is_empty() {
            SourceState::Ok
        } else if failed == files {
            SourceState::QueryFailed
        } else {
            SourceState::MissingValidRows
        };
        let error = if failed > 0 {
            Some("conversation_query_failed")
        } else if skipped > 0 {
            Some("rows_skipped_unrecognized_format")
        } else {
            None
        };
        (facts, diagnostic(self.key, state, files, records, error))
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

fn conversation_databases(dir: &Path) -> Vec<PathBuf> {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return vec![];
    };
    let mut files: Vec<_> = entries
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| path.is_file() && path.extension().is_some_and(|ext| ext == "db"))
        .collect();
    files.sort();
    files
}

fn open_read_only(path: &Path) -> rusqlite::Result<Connection> {
    Connection::open_with_flags(
        path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )
}

/// conversation_id -> 工作区本地路径，仅用于生成脱敏项目名；读取失败时返回空表。
fn workspace_paths(summary_db: &Path) -> HashMap<String, String> {
    let Ok(connection) = open_read_only(summary_db) else {
        return HashMap::new();
    };
    let Ok(mut statement) =
        connection.prepare("select conversation_id, workspace_uris from conversation_summaries")
    else {
        return HashMap::new();
    };
    let Ok(rows) = statement.query_map([], |row| {
        Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
    }) else {
        return HashMap::new();
    };
    rows.filter_map(Result::ok)
        .filter_map(|(id, uris)| first_workspace_path(&uris).map(|path| (id, path)))
        .collect()
}

fn first_workspace_path(uris: &str) -> Option<String> {
    let start = uris.find("file://")?;
    let uri: String = uris[start + "file://".len()..]
        .chars()
        .take_while(|ch| !matches!(ch, '"' | ',' | ']' | '\n' | '\r' | ' '))
        .collect();
    let path = percent_decode(&uri);
    // file:///c:/work -> /c:/work；Windows 盘符前的斜杠去掉。
    let path = match path.as_bytes() {
        [b'/', drive, b':', ..] if drive.is_ascii_alphabetic() => path[1..].to_owned(),
        _ => path,
    };
    (!path.is_empty()).then_some(path)
}

fn percent_decode(value: &str) -> String {
    let bytes = value.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            let hex = std::str::from_utf8(&bytes[i + 1..i + 3]).ok();
            if let Some(byte) = hex.and_then(|hex| u8::from_str_radix(hex, 16).ok()) {
                out.push(byte);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn query_conversation(
    source: &AntigravitySource,
    path: &Path,
    conversation_id: &str,
    workspace: Option<&str>,
) -> Result<(Vec<UsageFact>, u64), &'static str> {
    let connection = open_read_only(path).map_err(|_| "database_open_failed")?;
    let step_times = step_times(&connection)?;
    let mut statement = connection
        .prepare("select idx, data from gen_metadata order by idx")
        .map_err(|_| "schema_mismatch")?;
    let rows = statement
        .query_map([], |row| {
            Ok((row.get::<_, i64>(0)?, row.get::<_, Vec<u8>>(1)?))
        })
        .map_err(|_| "query_failed")?;
    let shanghai = FixedOffset::east_opt(8 * 3600).unwrap();
    let mut facts = Vec::new();
    let mut skipped = 0;
    for row in rows {
        let (idx, data) = row.map_err(|_| "invalid_usage_row")?;
        let Some(generation) = parse_generation(&data) else {
            skipped += 1;
            continue;
        };
        let Some(&seconds) = step_times.get(&generation.step_index) else {
            skipped += 1;
            continue;
        };
        let Some(timestamp) = DateTime::<Utc>::from_timestamp(seconds, 0) else {
            skipped += 1;
            continue;
        };
        if generation.tokens.is_empty() {
            continue;
        }
        let call_id = generation.call_id.unwrap_or_else(|| idx.to_string());
        facts.push(UsageFact {
            occurred_at: timestamp.to_rfc3339(),
            local_date: timestamp
                .with_timezone(&shanghai)
                .format("%Y-%m-%d")
                .to_string(),
            agent_key: source.key.into(),
            agent_name: source.name.into(),
            model: generation.model,
            project_key: project_key(workspace),
            project_name: project_name(workspace),
            source_event_id: format!("{}:{conversation_id}:{call_id}", source.key),
            tokens: generation.tokens,
        });
    }
    Ok((facts, skipped))
}

/// steps.idx -> epoch 秒（metadata 的 1.1）。只查询 metadata 列。
fn step_times(connection: &Connection) -> Result<HashMap<i64, i64>, &'static str> {
    let mut statement = connection
        .prepare("select idx, metadata from steps")
        .map_err(|_| "schema_mismatch")?;
    let rows = statement
        .query_map([], |row| {
            Ok((row.get::<_, i64>(0)?, row.get::<_, Option<Vec<u8>>>(1)?))
        })
        .map_err(|_| "query_failed")?;
    let mut times = HashMap::new();
    for row in rows {
        let (idx, metadata) = row.map_err(|_| "invalid_step_row")?;
        let seconds = metadata
            .as_deref()
            .and_then(|buf| message(buf, 1))
            .and_then(|created| varint(created, 1))
            .and_then(|value| i64::try_from(value).ok());
        if let Some(seconds) = seconds {
            times.insert(idx, seconds);
        }
    }
    Ok(times)
}

#[derive(Debug)]
struct Generation {
    model: String,
    call_id: Option<String>,
    step_index: i64,
    tokens: TokenCounts,
}

fn parse_generation(data: &[u8]) -> Option<Generation> {
    let body = message(data, 1)?;
    let usage = message(body, 4)?;
    let model = string(body, 19).filter(|name| !name.is_empty())?;
    let step_index = fields(body)?
        .into_iter()
        .filter(|(number, _)| *number == 20)
        .filter_map(|(_, value)| match value {
            Value::Bytes(entry) => Some(entry),
            Value::Varint(_) => None,
        })
        .find(|entry| string(entry, 1).as_deref() == Some("last_step_index"))
        .and_then(|entry| string(entry, 2))
        .and_then(|value| value.parse::<i64>().ok())?;
    let input = varint(usage, 2)?;
    let output = varint(usage, 3)?;
    let cache_read = varint(usage, 5).unwrap_or(0);
    Some(Generation {
        model,
        call_id: string(usage, 7),
        step_index,
        tokens: TokenCounts::from_components(input, output, cache_read, 0),
    })
}

// --- 最小 protobuf wire 解析：只支持 varint / 定长 / length-delimited，失败即放弃该行 ---

enum Value<'a> {
    Varint(u64),
    Bytes(&'a [u8]),
}

fn read_varint(buf: &[u8], pos: &mut usize) -> Option<u64> {
    let mut result = 0u64;
    for shift in (0..64).step_by(7) {
        let byte = *buf.get(*pos)?;
        *pos += 1;
        result |= u64::from(byte & 0x7f) << shift;
        if byte & 0x80 == 0 {
            return Some(result);
        }
    }
    None
}

fn fields(buf: &[u8]) -> Option<Vec<(u64, Value<'_>)>> {
    let mut out = Vec::new();
    let mut pos = 0;
    while pos < buf.len() {
        let key = read_varint(buf, &mut pos)?;
        let number = key >> 3;
        match key & 7 {
            0 => out.push((number, Value::Varint(read_varint(buf, &mut pos)?))),
            1 => pos = pos.checked_add(8).filter(|end| *end <= buf.len())?,
            2 => {
                let len = usize::try_from(read_varint(buf, &mut pos)?).ok()?;
                let end = pos.checked_add(len).filter(|end| *end <= buf.len())?;
                out.push((number, Value::Bytes(&buf[pos..end])));
                pos = end;
            }
            5 => pos = pos.checked_add(4).filter(|end| *end <= buf.len())?,
            _ => return None,
        }
    }
    Some(out)
}

fn message(buf: &[u8], number: u64) -> Option<&[u8]> {
    fields(buf)?.into_iter().find_map(|(n, value)| match value {
        Value::Bytes(bytes) if n == number => Some(bytes),
        _ => None,
    })
}

fn varint(buf: &[u8], number: u64) -> Option<u64> {
    fields(buf)?.into_iter().find_map(|(n, value)| match value {
        Value::Varint(v) if n == number => Some(v),
        _ => None,
    })
}

fn string(buf: &[u8], number: u64) -> Option<String> {
    message(buf, number).and_then(|bytes| String::from_utf8(bytes.to_vec()).ok())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn encode_varint(mut value: u64, out: &mut Vec<u8>) {
        loop {
            let byte = (value & 0x7f) as u8;
            value >>= 7;
            if value == 0 {
                out.push(byte);
                return;
            }
            out.push(byte | 0x80);
        }
    }

    fn int(number: u64, value: u64) -> Vec<u8> {
        let mut out = Vec::new();
        encode_varint(number << 3, &mut out);
        encode_varint(value, &mut out);
        out
    }

    fn bytes(number: u64, payload: &[u8]) -> Vec<u8> {
        let mut out = Vec::new();
        encode_varint((number << 3) | 2, &mut out);
        encode_varint(payload.len() as u64, &mut out);
        out.extend_from_slice(payload);
        out
    }

    fn flag(key: &str, value: &str) -> Vec<u8> {
        bytes(
            20,
            &[bytes(1, key.as_bytes()), bytes(2, value.as_bytes())].concat(),
        )
    }

    fn generation(step: i64, input: u64, output: u64, cache: Option<u64>) -> Vec<u8> {
        let mut usage = [int(1, 1318), int(2, input), int(3, output)].concat();
        if let Some(cache) = cache {
            usage.extend(int(5, cache));
        }
        usage.extend(bytes(7, format!("bot-{step}").as_bytes()));
        let body = [
            bytes(4, &usage),
            bytes(19, b"gemini-3.8-flash-n"),
            flag("used_claude", "false"),
            flag("last_step_index", &step.to_string()),
        ]
        .concat();
        bytes(1, &body)
    }

    fn fixture(dir: &Path, product: &str) -> PathBuf {
        let root = dir.join(".gemini").join(product);
        std::fs::create_dir_all(root.join("conversations")).unwrap();
        let db_path = root.join("conversations/conv-1.db");
        let db = Connection::open(&db_path).unwrap();
        db.execute_batch(
            "create table gen_metadata (idx integer primary key, data blob, size integer);
             create table steps (idx integer primary key, step_type integer, metadata blob, step_payload blob);",
        )
        .unwrap();
        // 2026-10-05T10:56:55Z = 上海 18:56；第二次调用跨过上海午夜。
        for (idx, seconds) in [(0i64, 1_791_197_815u64), (2, 1_791_224_400)] {
            let meta = bytes(1, &[int(1, seconds), int(2, 5)].concat());
            db.execute(
                "insert into steps values (?1, 15, ?2, x'73656372657420707269766174652074657874')",
                rusqlite::params![idx, meta],
            )
            .unwrap();
        }
        let rows = [
            generation(0, 2000, 300, None),
            generation(2, 1500, 200, Some(12000)),
            generation(99, 10, 10, None), // 指向不存在的步骤 -> 跳过
            b"\xff\xff".to_vec(),         // 无法解析 -> 跳过
        ];
        for (idx, data) in rows.iter().enumerate() {
            db.execute(
                "insert into gen_metadata values (?1, ?2, 0)",
                rusqlite::params![idx as i64, data],
            )
            .unwrap();
        }
        drop(db);
        let summary = Connection::open(root.join("conversation_summaries.db")).unwrap();
        summary
            .execute_batch(
                r#"create table conversation_summaries (conversation_id text, workspace_uris text);
                   insert into conversation_summaries values ('conv-1', '["file:///c%3A/code/token%20hub"]');"#,
            )
            .unwrap();
        root
    }

    #[test]
    fn maps_usage_model_time_and_workspace_without_guessing() {
        let dir = TempDir::new().unwrap();
        fixture(dir.path(), "antigravity");
        let source = AntigravitySource::new(PlatformPaths::new(dir.path(), None));
        let (facts, diag) = source.collect();

        assert_eq!(diag.state, SourceState::Ok);
        assert_eq!(diag.files, 1);
        assert_eq!(diag.records, 2);
        assert_eq!(
            diag.safe_error.as_deref(),
            Some("rows_skipped_unrecognized_format")
        );

        let first = &facts[0];
        assert_eq!(first.model, "gemini-3.8-flash-n");
        assert_eq!(first.local_date, "2026-10-05");
        assert_eq!(first.project_name, "token hub");
        assert_eq!(first.source_event_id, "antigravity:conv-1:bot-0");
        assert_eq!(first.tokens.total_tokens, 2300);

        let second = &facts[1];
        assert_eq!(second.local_date, "2026-10-06");
        assert_eq!(second.tokens.input_tokens, 1500);
        assert_eq!(second.tokens.cache_read_tokens, 12000);
        assert_eq!(second.tokens.output_tokens, 200);
        assert_eq!(second.tokens.total_tokens, 13700);
    }

    #[test]
    fn ide_reads_its_own_directory_under_a_separate_agent() {
        let dir = TempDir::new().unwrap();
        fixture(dir.path(), "antigravity-ide");
        let paths = PlatformPaths::new(dir.path(), None);

        let (facts, diag) = AntigravitySource::ide(paths.clone()).collect();
        assert_eq!(diag.agent_key, "antigravity_ide");
        assert_eq!(diag.state, SourceState::Ok);
        assert_eq!(facts.len(), 2);
        assert_eq!(facts[0].agent_name, "Antigravity IDE");
        assert_eq!(facts[0].source_event_id, "antigravity_ide:conv-1:bot-0");

        let (facts, diag) = AntigravitySource::new(paths).collect();
        assert!(facts.is_empty());
        assert_eq!(diag.state, SourceState::Missing);
    }

    #[test]
    fn missing_directory_reports_missing() {
        let dir = TempDir::new().unwrap();
        let (facts, diag) = AntigravitySource::new(PlatformPaths::new(dir.path(), None)).collect();
        assert!(facts.is_empty());
        assert_eq!(diag.state, SourceState::Missing);
    }

    #[test]
    fn workspace_uri_decoding() {
        assert_eq!(
            first_workspace_path("file:///c%3A/work/demo").as_deref(),
            Some("c:/work/demo")
        );
        assert_eq!(
            first_workspace_path("[\"file:///Users/a/proj\"]").as_deref(),
            Some("/Users/a/proj")
        );
        assert_eq!(first_workspace_path(""), None);
    }
}
