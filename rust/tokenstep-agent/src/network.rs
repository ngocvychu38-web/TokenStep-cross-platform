use anyhow::Result;
use reqwest::blocking::Client;

pub fn client() -> Result<Client> {
    let builder = Client::builder()
        .connect_timeout(std::time::Duration::from_secs(10))
        .timeout(std::time::Duration::from_secs(30))
        .redirect(reqwest::redirect::Policy::none());
    #[cfg(target_os = "macos")]
    let builder = if !["HTTPS_PROXY", "https_proxy", "ALL_PROXY", "all_proxy"]
        .iter()
        .any(|key| std::env::var_os(key).is_some())
    {
        let settings = std::process::Command::new("/usr/sbin/scutil")
            .arg("--proxy")
            .output()?;
        if let Some(proxy) = system_https_proxy(&String::from_utf8_lossy(&settings.stdout)) {
            println!("network_config proxy=macos_system tls=1.2");
            builder
                .proxy(reqwest::Proxy::https(proxy)?)
                .min_tls_version(reqwest::tls::Version::TLS_1_2)
                .max_tls_version(reqwest::tls::Version::TLS_1_2)
        } else {
            builder
        }
    } else {
        builder
    };
    Ok(builder.build()?)
}

#[cfg(any(target_os = "macos", test))]
fn system_https_proxy(settings: &str) -> Option<String> {
    let value = |key: &str| {
        settings.lines().find_map(|line| {
            let (name, value) = line.trim().split_once(" : ")?;
            (name == key).then(|| value.trim())
        })
    };
    if value("HTTPSEnable")? != "1" {
        return None;
    }
    let host = value("HTTPSProxy")?;
    let port: u16 = value("HTTPSPort")?.parse().ok()?;
    if port == 0
        || host.is_empty()
        || !host
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || ".-".contains(c))
    {
        return None;
    }
    Some(format!("http://{host}:{port}"))
}

#[cfg(test)]
mod tests {
    #[test]
    fn system_proxy_configuration() {
        assert_eq!(
            super::system_https_proxy("HTTPSEnable : 1\nHTTPSProxy : 127.0.0.1\nHTTPSPort : 7897"),
            Some("http://127.0.0.1:7897".into())
        );
        assert!(
            super::system_https_proxy("HTTPSEnable : 0\nHTTPSProxy : localhost\nHTTPSPort : 7897")
                .is_none()
        );
        assert!(
            super::system_https_proxy(
                "HTTPSEnable : 1\nHTTPSProxy : user:secret@host\nHTTPSPort : 7897"
            )
            .is_none()
        );
    }
    #[test]
    #[ignore = "requires the deployed backend and current host network"]
    fn deployed_ingest_connection() {
        let response = super::client()
            .unwrap()
            .get("https://hdizeqfyrdfbqohrnuzt.supabase.co/functions/v1/ingest-usage")
            .send()
            .expect("upload transport must reach the server without a connection reset");
        assert_eq!(response.status().as_u16(), 405);
    }
}
