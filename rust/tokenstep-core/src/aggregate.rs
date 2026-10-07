use std::collections::BTreeMap;

use crate::{CONTRACT_VERSION, HourlyUsage, TokenCounts, UsageBucketV1, UsageFact};
use chrono::{DateTime, FixedOffset, Timelike};

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
struct BucketKey {
    local_date: String,
    agent_key: String,
    agent_name: String,
    model: String,
    project_key: String,
    project_name: String,
}

pub fn aggregate_facts(
    facts: impl IntoIterator<Item = UsageFact>,
    timezone: &str,
) -> Vec<UsageBucketV1> {
    type Aggregate = (TokenCounts, u64, BTreeMap<u32, (TokenCounts, u64)>);
    let mut grouped: BTreeMap<BucketKey, Aggregate> = BTreeMap::new();
    for fact in facts {
        if fact.tokens.is_empty() {
            continue;
        }
        let key = BucketKey {
            local_date: fact.local_date,
            agent_key: fact.agent_key,
            agent_name: fact.agent_name,
            model: fact.model,
            project_key: fact.project_key,
            project_name: fact.project_name,
        };
        let entry = grouped.entry(key).or_default();
        entry.0.add_assign(&fact.tokens);
        entry.1 += 1;
        if let Ok(time) = DateTime::parse_from_rfc3339(&fact.occurred_at) {
            let hour = time
                .with_timezone(&FixedOffset::east_opt(8 * 3600).unwrap())
                .hour();
            let hourly = entry.2.entry(hour).or_default();
            hourly.0.add_assign(&fact.tokens);
            hourly.1 += 1;
        }
    }

    grouped
        .into_iter()
        .map(|(key, (tokens, record_count, hours))| UsageBucketV1 {
            schema_version: CONTRACT_VERSION,
            local_date: key.local_date,
            timezone: timezone.to_owned(),
            agent_key: key.agent_key,
            agent_name: key.agent_name,
            model: key.model,
            project_key: key.project_key,
            project_name: key.project_name,
            tokens,
            record_count,
            hourly_usage: hours
                .into_iter()
                .map(|(hour, (tokens, record_count))| HourlyUsage {
                    hour,
                    tokens,
                    record_count,
                })
                .collect(),
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preserves_joint_dimensions_and_sums_matching_facts() {
        let fact = UsageFact {
            occurred_at: "2026-10-06T01:00:00Z".into(),
            local_date: "2026-10-06".into(),
            agent_key: "teleagent".into(),
            agent_name: "TeleAgent".into(),
            model: "gpt-5".into(),
            project_key: "p1".into(),
            project_name: "tokenhub".into(),
            source_event_id: "m1".into(),
            tokens: TokenCounts::from_components(10, 5, 2, 1),
        };
        let buckets = aggregate_facts(
            [
                fact.clone(),
                UsageFact {
                    source_event_id: "m2".into(),
                    ..fact
                },
            ],
            "Asia/Shanghai",
        );
        assert_eq!(buckets.len(), 1);
        assert_eq!(buckets[0].tokens.total_tokens, 36);
        assert_eq!(buckets[0].record_count, 2);
        assert_eq!(buckets[0].project_name, "tokenhub");
        assert_eq!(buckets[0].hourly_usage[0].hour, 9);
        assert_eq!(buckets[0].hourly_usage[0].tokens.total_tokens, 36);
    }
}
