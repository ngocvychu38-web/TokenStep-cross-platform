use std::path::Path;

use anyhow::Result;
use rusqlite::Connection;
use tokenstep_core::CollectionSnapshot;

pub struct Outbox(Connection);

impl Outbox {
    pub fn open(directory: &Path) -> Result<Self> {
        std::fs::create_dir_all(directory)?;
        let connection = Connection::open(directory.join("outbox.sqlite3"))?;
        connection.execute_batch("create table if not exists batches (id integer primary key autoincrement, payload text not null, created_at text not null);")?;
        Ok(Self(connection))
    }

    pub fn enqueue(&self, snapshot: &CollectionSnapshot) -> Result<()> {
        self.0.execute(
            "insert into batches(payload, created_at) values (?1, ?2)",
            rusqlite::params![serde_json::to_string(snapshot)?, snapshot.generated_at],
        )?;
        Ok(())
    }

    pub fn oldest(&self) -> Result<Option<(i64, CollectionSnapshot)>> {
        let mut query = self
            .0
            .prepare("select id, payload from batches order by id limit 1")?;
        let mut rows = query.query([])?;
        let Some(row) = rows.next()? else {
            return Ok(None);
        };
        let payload: String = row.get(1)?;
        Ok(Some((row.get(0)?, serde_json::from_str(&payload)?)))
    }

    pub fn acknowledge(&self, id: i64) -> Result<()> {
        self.0.execute("delete from batches where id = ?1", [id])?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokenstep_core::DeviceDescriptor;

    #[test]
    fn unacknowledged_batch_survives_restart() {
        let directory =
            std::env::temp_dir().join(format!("tokenstep-outbox-{}", uuid::Uuid::new_v4()));
        let snapshot = CollectionSnapshot {
            schema_version: 1,
            generated_at: "2026-10-06T01:00:00Z".into(),
            timezone: "Asia/Shanghai".into(),
            device: DeviceDescriptor {
                device_id: "d1".into(),
                display_name: "test".into(),
                os_family: "macos".into(),
                os_version: "14".into(),
                architecture: "x86_64".into(),
                collector_version: "1".into(),
            },
            buckets: vec![],
            sources: vec![],
        };
        let queue = Outbox::open(&directory).unwrap();
        queue.enqueue(&snapshot).unwrap();
        drop(queue);
        let queue = Outbox::open(&directory).unwrap();
        let (id, recovered) = queue.oldest().unwrap().unwrap();
        assert_eq!(recovered, snapshot);
        queue.acknowledge(id).unwrap();
        assert!(queue.oldest().unwrap().is_none());
        drop(queue);
        std::fs::remove_dir_all(directory).unwrap();
    }
}
