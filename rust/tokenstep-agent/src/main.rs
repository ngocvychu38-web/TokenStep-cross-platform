use std::{
    env, fs,
    path::{Path, PathBuf},
};

use anyhow::{Context, Result, bail};
use chrono::Utc;
use clap::{Parser, Subcommand};
use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use tokenstep_core::OpenCodeSource;
use tokenstep_core::{
    CONTRACT_VERSION, ClaudeCodeSource, CodexSource, CollectionSnapshot, Collector,
    DeviceDescriptor, PlatformPaths, SourceAdapter, TeleAgentSource, aggregate_facts,
};
use uuid::Uuid;
mod outbox;

#[derive(Parser)]
#[command(
    name = "tokenstep-agent",
    version,
    about = "Cross-platform local AI token collector"
)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Verify the native credential store using a disposable, non-production entry.
    VaultCheck,
    /// Persist a collection in the offline queue and upload pending batches in order.
    Cycle {
        #[arg(long)]
        ingest_url: String,
        #[arg(long)]
        state_dir: Option<PathBuf>,
        #[arg(long)]
        home: Option<PathBuf>,
    },
    /// Collect local usage metadata and write a verifiable JSON snapshot.
    Collect {
        #[arg(long)]
        home: Option<PathBuf>,
        #[arg(long)]
        output: PathBuf,
        #[arg(long, default_value = "Asia/Shanghai")]
        timezone: String,
        #[arg(long)]
        state_dir: Option<PathBuf>,
    },
    /// Validate a snapshot without sending it anywhere.
    Verify {
        #[arg(long)]
        input: PathBuf,
    },
    /// Print source discovery and collection status without prompt/response content.
    Doctor {
        #[arg(long)]
        home: Option<PathBuf>,
        #[arg(long)]
        state_dir: Option<PathBuf>,
    },
    /// Exchange a short-lived enrollment code for this device's upload credential.
    Enroll {
        #[arg(long)]
        enrollment_url: String,
        #[arg(long)]
        code: String,
        #[arg(long)]
        state_dir: Option<PathBuf>,
    },
    /// Upload a previously verified snapshot to the configured ingestion function.
    Sync {
        #[arg(long)]
        input: PathBuf,
        #[arg(long)]
        ingest_url: Option<String>,
        #[arg(long, hide_env_values = true)]
        device_token: Option<String>,
        #[arg(long)]
        state_dir: Option<PathBuf>,
    },
}

#[derive(Debug, Serialize, Deserialize)]
struct LocalAgentState {
    device_id: String,
    display_name: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct LocalCredentials {
    device_token: String,
    workspace_id: String,
}

#[derive(Debug, Deserialize)]
struct EnrollmentResponse {
    device_id: String,
    workspace_id: String,
    device_token: String,
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Commands::VaultCheck => {
            let account = format!("verification-{}", Uuid::new_v4());
            let entry = keyring::Entry::new("TokenStep.VaultVerification", &account)?;
            entry.set_password("disposable-verification-value")?;
            let result = entry.get_password();
            entry.delete_credential()?;
            if result? != "disposable-verification-value" {
                bail!("credential store round-trip mismatch");
            }
            println!("vault_ok native credential store round-trip verified; test entry removed");
        }
        Commands::Cycle {
            ingest_url,
            state_dir,
            home,
        } => {
            validate_endpoint(&ingest_url)?;
            let directory = state_dir.unwrap_or_else(default_state_dir);
            let snapshot = collect_snapshot(home, Some(directory.clone()), "Asia/Shanghai")?;
            verify_snapshot(&snapshot)?;
            let queue = outbox::Outbox::open(&directory)?;
            queue.enqueue(&snapshot)?;
            write_json(&directory.join("snapshot.json"), &snapshot)?;
            let credential = read_credentials(&directory)?;
            let client = Client::builder()
                .timeout(std::time::Duration::from_secs(60))
                .build()?;
            while let Some((id, pending)) = queue.oldest()? {
                let response = client
                    .post(&ingest_url)
                    .bearer_auth(&credential.device_token)
                    .json(&pending)
                    .send()?;
                if !response.status().is_success() {
                    bail!(
                        "upload rejected {}; batch remains in offline queue",
                        response.status()
                    );
                }
                // A malformed acknowledgement must not discard a durable batch.
                let acknowledgement: serde_json::Value = response.json()?;
                if acknowledgement
                    .get("accepted")
                    .and_then(serde_json::Value::as_u64)
                    .is_none()
                {
                    bail!("invalid server acknowledgement; batch remains in offline queue");
                }
                queue.acknowledge(id)?;
                println!("batch_acknowledged id={id}");
            }
            println!("cycle_ok");
        }
        Commands::Collect {
            home,
            output,
            timezone,
            state_dir,
        } => {
            let snapshot = collect_snapshot(home, state_dir, &timezone)?;
            verify_snapshot(&snapshot)?;
            write_json(&output, &snapshot)?;
            println!(
                "collection_ok buckets={} sources={} output={}",
                snapshot.buckets.len(),
                snapshot.sources.len(),
                output.display()
            );
        }
        Commands::Verify { input } => {
            let snapshot: CollectionSnapshot = read_json(&input)?;
            verify_snapshot(&snapshot)?;
            let total: u64 = snapshot
                .buckets
                .iter()
                .map(|row| row.tokens.total_tokens)
                .sum();
            println!(
                "verification_ok device={} buckets={} total_tokens={total}",
                snapshot.device.display_name,
                snapshot.buckets.len()
            );
        }
        Commands::Doctor { home, state_dir } => {
            let snapshot = collect_snapshot(home, state_dir, "Asia/Shanghai")?;
            println!(
                "device={} os={} arch={}",
                snapshot.device.display_name,
                snapshot.device.os_family,
                snapshot.device.architecture
            );
            for source in snapshot.sources {
                println!(
                    "source={} state={:?} files={} records={}",
                    source.agent_key, source.state, source.files, source.records
                );
            }
        }
        Commands::Enroll {
            enrollment_url,
            code,
            state_dir,
        } => {
            validate_endpoint(&enrollment_url)?;
            let directory = state_dir.unwrap_or_else(default_state_dir);
            let state = load_or_create_state(directory.clone())?;
            let device = device_descriptor(&state);
            let response = Client::builder()
                .build()?
                .post(enrollment_url)
                .json(&serde_json::json!({ "enrollment_code": code, "device": device }))
                .send()
                .context("device enrollment request failed")?;
            let status = response.status();
            if !status.is_success() {
                bail!("device enrollment failed with {status}");
            }
            let enrollment: EnrollmentResponse = response.json()?;
            if enrollment.device_id != state.device_id {
                bail!("server returned a different device id");
            }
            write_credentials(
                &directory,
                &LocalCredentials {
                    device_token: enrollment.device_token,
                    workspace_id: enrollment.workspace_id,
                },
            )?;
            println!("enrollment_ok device_id={}", state.device_id);
        }
        Commands::Sync {
            input,
            ingest_url,
            device_token,
            state_dir,
        } => {
            let ingest_url = ingest_url
                .or_else(|| env::var("TOKENSTEP_INGEST_URL").ok())
                .context("set --ingest-url or TOKENSTEP_INGEST_URL")?;
            validate_endpoint(&ingest_url)?;
            let device_token = device_token
                .or_else(|| env::var("TOKENSTEP_DEVICE_TOKEN").ok())
                .or_else(|| {
                    read_credentials(&state_dir.unwrap_or_else(default_state_dir))
                        .ok()
                        .map(|value| value.device_token)
                })
                .context("set --device-token or TOKENSTEP_DEVICE_TOKEN")?;
            let snapshot: CollectionSnapshot = read_json(&input)?;
            verify_snapshot(&snapshot)?;
            let response = Client::builder()
                .build()?
                .post(ingest_url)
                .header("Authorization", format!("Bearer {device_token}"))
                .json(&snapshot)
                .send()
                .context("ingestion request failed")?;
            let status = response.status();
            let body = response.text().unwrap_or_default();
            if !status.is_success() {
                bail!("ingestion failed with {status}: {body}");
            }
            println!("sync_ok status={status} response={body}");
        }
    }
    Ok(())
}

fn collect_snapshot(
    home: Option<PathBuf>,
    state_dir: Option<PathBuf>,
    timezone: &str,
) -> Result<CollectionSnapshot> {
    if timezone != "Asia/Shanghai" {
        bail!("this contract currently supports Asia/Shanghai only");
    }
    let home = home.unwrap_or_else(default_home);
    let local_app_data = env::var_os("LOCALAPPDATA").map(PathBuf::from);
    let paths = PlatformPaths::new(home, local_app_data);
    let mut adapters: Vec<Box<dyn SourceAdapter>> = tokenstep_core::JsonAgentSource::all(&paths);
    adapters.extend(vec![
        Box::new(CodexSource::new(paths.clone())) as Box<dyn SourceAdapter>,
        Box::new(ClaudeCodeSource::new(paths.clone())) as Box<dyn SourceAdapter>,
        Box::new(TeleAgentSource::new(paths.clone())),
        Box::new(OpenCodeSource::new(paths)),
    ]);
    let (facts, sources) = Collector::new(adapters).collect();
    let state = load_or_create_state(state_dir.unwrap_or_else(default_state_dir))?;
    Ok(CollectionSnapshot {
        schema_version: CONTRACT_VERSION,
        generated_at: Utc::now().to_rfc3339(),
        timezone: timezone.into(),
        device: device_descriptor(&state),
        buckets: aggregate_facts(facts, timezone),
        sources,
    })
}

fn verify_snapshot(snapshot: &CollectionSnapshot) -> Result<()> {
    if snapshot.schema_version != CONTRACT_VERSION {
        bail!("unsupported schema version {}", snapshot.schema_version);
    }
    if snapshot.device.device_id.trim().is_empty() {
        bail!("device_id is required");
    }
    for bucket in &snapshot.buckets {
        if bucket.schema_version != CONTRACT_VERSION {
            bail!("bucket schema version mismatch");
        }
        if bucket.local_date.len() != 10 {
            bail!("invalid local_date {}", bucket.local_date);
        }
        if bucket.project_name.contains('/')
            || bucket.project_name.contains('\\')
            || bucket.project_name.contains(':')
        {
            bail!("project_name contains a path separator");
        }
        if bucket.agent_key.is_empty() || bucket.tokens.total_tokens == 0 {
            bail!("invalid empty usage bucket");
        }
    }
    Ok(())
}

fn load_or_create_state(directory: PathBuf) -> Result<LocalAgentState> {
    let path = directory.join("agent.json");
    if path.exists() {
        return read_json(&path);
    }
    fs::create_dir_all(&directory)?;
    let state = LocalAgentState {
        device_id: Uuid::new_v4().to_string(),
        display_name: hostname(),
    };
    write_json(&path, &state)?;
    Ok(state)
}

fn device_descriptor(state: &LocalAgentState) -> DeviceDescriptor {
    DeviceDescriptor {
        device_id: state.device_id.clone(),
        display_name: state.display_name.clone(),
        os_family: env::consts::OS.into(),
        os_version: os_version(),
        architecture: env::consts::ARCH.into(),
        collector_version: env!("CARGO_PKG_VERSION").into(),
    }
}

fn read_credentials(directory: &Path) -> Result<LocalCredentials> {
    let secret = credential_entry(directory)?.get_password().context(
        "cannot read device credential from system credential store; enroll this device first",
    )?;
    serde_json::from_str(&secret).context("invalid stored credential")
}

fn validate_endpoint(raw: &str) -> Result<()> {
    let url = reqwest::Url::parse(raw).context("invalid endpoint URL")?;
    if url.scheme() != "https"
        || url.host_str().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
    {
        bail!("endpoint must be HTTPS without embedded credentials");
    }
    Ok(())
}

fn write_credentials(directory: &Path, credentials: &LocalCredentials) -> Result<()> {
    credential_entry(directory)?
        .set_password(&serde_json::to_string(credentials)?)
        .context(
            "cannot save device credential in system credential store; no plaintext fallback",
        )?;
    Ok(())
}

fn credential_entry(directory: &Path) -> Result<keyring::Entry> {
    let state: LocalAgentState = read_json(&directory.join("agent.json"))?;
    keyring::Entry::new("TokenStep.DeviceUpload", &state.device_id)
        .context("system credential store is unavailable")
}

fn read_json<T: for<'de> Deserialize<'de>>(path: &Path) -> Result<T> {
    let bytes = fs::read(path).with_context(|| format!("failed to read {}", path.display()))?;
    serde_json::from_slice(&bytes).with_context(|| format!("invalid JSON in {}", path.display()))
}

fn write_json<T: Serialize>(path: &Path, value: &T) -> Result<()> {
    if let Some(parent) = path.parent().filter(|p| !p.as_os_str().is_empty()) {
        fs::create_dir_all(parent)?;
    }
    let bytes = serde_json::to_vec_pretty(value)?;
    use std::io::Write;
    let parent = path
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    let mut temporary = tempfile::NamedTempFile::new_in(parent)?;
    temporary.write_all(&bytes)?;
    temporary.as_file().sync_all()?;
    temporary.persist(path).map_err(|error| error.error)?;
    Ok(())
}

fn default_home() -> PathBuf {
    env::var_os("HOME")
        .or_else(|| env::var_os("USERPROFILE"))
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."))
}

fn default_state_dir() -> PathBuf {
    #[cfg(target_os = "windows")]
    {
        return env::var_os("LOCALAPPDATA")
            .map(PathBuf::from)
            .unwrap_or_else(default_home)
            .join("TokenStep")
            .join("agent");
    }
    #[cfg(not(target_os = "windows"))]
    {
        default_home()
            .join("Library")
            .join("Application Support")
            .join("TokenStep")
            .join("agent")
    }
}

fn hostname() -> String {
    if let Ok(name) = env::var("COMPUTERNAME").or_else(|_| env::var("HOSTNAME"))
        && !name.trim().is_empty()
    {
        return name;
    }
    #[cfg(target_os = "macos")]
    if let Ok(result) = std::process::Command::new("/usr/sbin/scutil")
        .args(["--get", "ComputerName"])
        .output()
    {
        let name = String::from_utf8_lossy(&result.stdout).trim().to_owned();
        if result.status.success() && !name.is_empty() {
            return name;
        }
    }
    "TokenStep Device".into()
}

fn os_version() -> String {
    #[cfg(target_os = "macos")]
    {
        return std::process::Command::new("/usr/bin/sw_vers")
            .args(["-productVersion"])
            .output()
            .ok()
            .filter(|r| r.status.success())
            .map(|r| String::from_utf8_lossy(&r.stdout).trim().to_owned())
            .unwrap_or_else(|| "unknown".into());
    }
    #[cfg(target_os = "windows")]
    {
        return env::var("OS").unwrap_or_else(|_| "Windows".into());
    }
    #[allow(unreachable_code)]
    "unknown".into()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn snapshot_can_be_replaced_without_partial_json() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("snapshot.json");
        write_json(&path, &serde_json::json!({"version": 1})).unwrap();
        write_json(&path, &serde_json::json!({"version": 2})).unwrap();
        let value: serde_json::Value = read_json(&path).unwrap();
        assert_eq!(value["version"], 2);
    }

    #[test]
    fn rejects_project_paths_in_cloud_contract() {
        let mut snapshot = CollectionSnapshot {
            schema_version: 1,
            generated_at: Utc::now().to_rfc3339(),
            timezone: "Asia/Shanghai".into(),
            device: DeviceDescriptor {
                device_id: "d1".into(),
                display_name: "test".into(),
                os_family: "macos".into(),
                os_version: "1".into(),
                architecture: "x86_64".into(),
                collector_version: "1".into(),
            },
            buckets: vec![],
            sources: vec![],
        };
        let mut bucket = tokenstep_core::UsageBucketV1 {
            schema_version: 1,
            local_date: "2026-10-06".into(),
            timezone: "Asia/Shanghai".into(),
            agent_key: "codex".into(),
            agent_name: "Codex".into(),
            model: "gpt-5".into(),
            project_key: "p".into(),
            project_name: "secret/path".into(),
            tokens: tokenstep_core::TokenCounts::from_components(1, 1, 0, 0),
            record_count: 1,
        };
        snapshot.buckets.push(bucket.clone());
        assert!(verify_snapshot(&snapshot).is_err());
        bucket.project_name = "tokenhub".into();
        snapshot.buckets[0] = bucket;
        assert!(verify_snapshot(&snapshot).is_ok());
    }
}
