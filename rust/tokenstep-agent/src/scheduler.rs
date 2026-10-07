use anyhow::{Result, bail};
use std::path::Path;

pub fn install(state: &Path, ingest_url: &str, seconds: u32) -> Result<()> {
    if !(60..=86400).contains(&seconds) {
        bail!("interval must be between 60 and 86400 seconds");
    }
    #[cfg(target_os = "macos")]
    {
        use std::os::unix::fs::PermissionsExt;
        use std::{fs, io::Write, process::Command};
        let home = super::default_home();
        fs::create_dir_all(state.join("bin"))?;
        fs::create_dir_all(state.join("logs"))?;
        let executable = state.join("bin/tokenstep-agent");
        let bytes = fs::read(std::env::current_exe()?)?;
        let mut staged = tempfile::NamedTempFile::new_in(state.join("bin"))?;
        staged.write_all(&bytes)?;
        staged
            .as_file()
            .set_permissions(fs::Permissions::from_mode(0o755))?;
        staged.persist(&executable).map_err(|e| e.error)?;
        let agents = home.join("Library/LaunchAgents");
        fs::create_dir_all(&agents)?;
        let plist = agents.join("com.tokenstep.collector.plist");
        fs::write(
            &plist,
            specification(&executable, state, ingest_url, seconds),
        )?;
        let uid = Command::new("/usr/bin/id").arg("-u").output()?;
        let domain = format!("gui/{}", String::from_utf8_lossy(&uid.stdout).trim());
        let label = format!("{domain}/com.tokenstep.collector");
        // Missing old registration is normal during first installation.
        let _ = Command::new("/bin/launchctl")
            .args(["bootout", &label])
            .output();
        let result = Command::new("/bin/launchctl")
            .arg("bootstrap")
            .arg(&domain)
            .arg(&plist)
            .output()?;
        if !result.status.success() {
            bail!(
                "launchd bootstrap failed: {}",
                String::from_utf8_lossy(&result.stderr)
            );
        }
        println!(
            "schedule_installed interval_seconds={seconds} executable={} plist={}",
            executable.display(),
            plist.display()
        );
        Ok(())
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = (state, ingest_url);
        bail!("use script/windows/install-tokenstep-agent.ps1 on Windows");
    }
}

#[cfg(any(target_os = "macos", test))]
fn specification(executable: &Path, state: &Path, ingest_url: &str, seconds: u32) -> String {
    let arguments = [
        executable.to_string_lossy().into_owned(),
        "cycle".into(),
        "--state-dir".into(),
        state.to_string_lossy().into_owned(),
        "--ingest-url".into(),
        ingest_url.into(),
    ]
    .iter()
    .map(|s| format!("<string>{}</string>", escape(s)))
    .collect::<String>();
    format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.tokenstep.collector</string>
<key>ProgramArguments</key><array>{arguments}</array>
<key>StartInterval</key><integer>{seconds}</integer>
<key>RunAtLoad</key><true/>
<key>ProcessType</key><string>Background</string>
<key>StandardOutPath</key><string>{}</string>
<key>StandardErrorPath</key><string>{}</string>
</dict></plist>"#,
        escape(&state.join("logs/agent.log").to_string_lossy()),
        escape(&state.join("logs/agent-error.log").to_string_lossy())
    )
}

#[cfg(any(target_os = "macos", test))]
fn escape(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&apos;")
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn schedule_escapes_paths_and_keeps_interval_configurable() {
        let test = specification(
            Path::new("/test & spaces/agent"),
            Path::new("/state"),
            "https://example.test/upload",
            60,
        );
        assert!(test.contains("/test &amp; spaces/agent"));
        assert!(test.contains("<integer>60</integer>"));
        assert!(
            specification(
                Path::new("/bin/agent"),
                Path::new("/state"),
                "https://example.test/upload",
                600
            )
            .contains("<integer>600</integer>")
        );
        assert!(!test.contains("device_token"));
    }
}
