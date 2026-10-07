use std::path::{Path, PathBuf};

#[derive(Debug, Clone)]
pub struct PlatformPaths {
    home: PathBuf,
    local_app_data: Option<PathBuf>,
}

impl PlatformPaths {
    pub fn new(home: impl Into<PathBuf>, local_app_data: Option<PathBuf>) -> Self {
        Self {
            home: home.into(),
            local_app_data,
        }
    }

    pub fn home(&self) -> &Path {
        &self.home
    }

    pub fn codex_sessions(&self) -> Vec<PathBuf> {
        vec![self.home.join(".codex").join("sessions")]
    }

    pub fn claude_projects(&self) -> Vec<PathBuf> {
        vec![self.home.join(".claude").join("projects")]
    }

    pub fn antigravity_root(&self) -> PathBuf {
        self.home.join(".gemini").join("antigravity")
    }

    pub fn teleagent_databases(&self) -> Vec<PathBuf> {
        let mut candidates = vec![
            self.home
                .join(".local")
                .join("share")
                .join("TeleAgent")
                .join("teleagent.db"),
        ];
        if let Some(local) = &self.local_app_data {
            candidates.extend([
                local.join("TeleAgent").join("teleagent.db"),
                local.join("teleagent").join("teleagent.db"),
            ]);
        }
        candidates
    }

    pub fn opencode_databases(&self) -> Vec<PathBuf> {
        let mut candidates = vec![self.home.join(".local/share/opencode/opencode.db")];
        if let Some(local) = &self.local_app_data {
            candidates.push(local.join("opencode/opencode.db"));
        }
        candidates
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn windows_candidates_include_local_app_data_without_losing_home_fallback() {
        let paths = PlatformPaths::new(
            "C:/Users/Alice",
            Some(PathBuf::from("C:/Users/Alice/AppData/Local")),
        );
        let candidates = paths.teleagent_databases();
        assert_eq!(candidates.len(), 3);
        assert!(candidates[0].ends_with(".local/share/TeleAgent/teleagent.db"));
        assert!(candidates[1].ends_with("TeleAgent/teleagent.db"));
    }
}
