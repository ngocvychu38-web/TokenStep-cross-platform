#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d /tmp/tokenstep-rust-verify.XXXXXX)"
trap 'rm -rf "$TEMP_DIR"' EXIT

cd "$ROOT_DIR"
cargo fmt --all -- --check
cargo test --workspace
cargo run -q -p tokenstep-agent -- collect \
  --output "$TEMP_DIR/snapshot.json" \
  --state-dir "$TEMP_DIR/state"
cargo run -q -p tokenstep-agent -- verify --input "$TEMP_DIR/snapshot.json"
cargo run -q -p tokenstep-agent -- doctor --state-dir "$TEMP_DIR/state"

echo "Rust collector verification passed."

