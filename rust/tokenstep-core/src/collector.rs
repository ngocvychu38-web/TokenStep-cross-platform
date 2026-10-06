use crate::{SourceDiagnostic, UsageFact};

pub trait SourceAdapter: Send + Sync {
    fn key(&self) -> &'static str;
    fn collect(&self) -> (Vec<UsageFact>, SourceDiagnostic);
}

#[derive(Default)]
pub struct Collector {
    adapters: Vec<Box<dyn SourceAdapter>>,
}

impl Collector {
    pub fn new(adapters: Vec<Box<dyn SourceAdapter>>) -> Self {
        Self { adapters }
    }

    pub fn collect(&self) -> (Vec<UsageFact>, Vec<SourceDiagnostic>) {
        let mut facts = Vec::new();
        let mut diagnostics = Vec::new();
        for adapter in &self.adapters {
            let (mut source_facts, diagnostic) = adapter.collect();
            facts.append(&mut source_facts);
            diagnostics.push(diagnostic);
        }
        (facts, diagnostics)
    }
}
