#!/bin/bash
set -euo pipefail
# Usage: script/package_internal_delivery.sh OUTPUT_DIR VERIFIED_WINDOWS_ZIP
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:?Provide an output directory}
WINDOWS=${2:?Provide the verified Windows installer ZIP}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
MAC="$OUT/TokenStep-0.2.0-macOS-Intel"
if [[ -e "$MAC" || -e "$OUT/TokenStep-0.2.0-macOS-Intel.zip" ]]; then
  echo 'Use a new output directory; existing Mac package will not be overwritten.' >&2
  exit 1
fi
file "$ROOT/target/release/tokenstep-agent" | grep -q x86_64
file "$ROOT/TokenStepSwift/dist/TokenStep.app/Contents/MacOS/TokenStepSwift" | grep -q x86_64
mkdir -p "$MAC" "$OUT/docs" "$OUT/supabase"
ditto "$ROOT/TokenStepSwift/dist/TokenStep.app" "$MAC/TokenStep.app"
cp "$ROOT/target/release/tokenstep-agent" "$MAC/tokenstep-agent"
cp "$ROOT/script/macos/configure-cloud.command" "$MAC/configure-cloud.command"
chmod +x "$MAC/tokenstep-agent" "$MAC/configure-cloud.command"
cp "$ROOT/docs/DEPLOYMENT_GUIDE.md" "$MAC/README-install.md"
cp "$WINDOWS" "$OUT/TokenStep-Agent-0.1.0-windows-x64.zip"
for name in PROJECT_HANDOVER PROJECT_OVERVIEW DEPLOYMENT_GUIDE DISTRIBUTION_MANIFEST PIPELINE_LOGS; do
  cp "$ROOT/docs/$name.md" "$OUT/docs/$name.md"
done
ditto "$ROOT/supabase/migrations" "$OUT/supabase/migrations"
ditto "$ROOT/supabase/functions" "$OUT/supabase/functions"
cp "$ROOT/supabase/config.toml" "$OUT/supabase/config.toml"
(
  cd "$MAC"
  shasum -a 256 tokenstep-agent configure-cloud.command TokenStep.app/Contents/MacOS/TokenStepSwift > SHA256SUMS.txt
)
ditto -c -k --keepParent "$MAC" "$OUT/TokenStep-0.2.0-macOS-Intel.zip"
(
  cd "$OUT"
  shasum -a 256 TokenStep-0.2.0-macOS-Intel.zip TokenStep-Agent-0.1.0-windows-x64.zip > SHA256SUMS.txt
)
echo "Internal delivery prepared: $OUT"

# Bundle sits outside OUT to avoid recursively including its own archive.
PARENT=$(dirname "$OUT")
BUNDLE="$PARENT/TokenStep-2026-10-11-delivery.zip"
if [[ -e "$BUNDLE" ]]; then
  echo 'Existing delivery archive preserved; choose a fresh parent directory.' >&2
  exit 1
fi
ditto -c -k --keepParent "$OUT" "$BUNDLE"
(
  cd "$PARENT"
  shasum -a 256 TokenStep-2026-10-11-delivery.zip > TokenStep-2026-10-11-delivery.SHA256SUMS.txt
)
