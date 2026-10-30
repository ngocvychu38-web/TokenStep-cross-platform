#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATION="$ROOT_DIR/supabase/migrations/202610060001_initial_cloud_schema.sql"

test -s "$MIGRATION"
test -s "$ROOT_DIR/supabase/functions/enroll-device/index.ts"
test -s "$ROOT_DIR/supabase/functions/ingest-usage/index.ts"

for required in \
  "create table public.devices" \
  "create table public.usage_buckets" \
  "enable row level security" \
  "create or replace function public.ingest_device_snapshot" \
  "security_invoker = true"; do
  grep -Fq "$required" "$MIGRATION"
done

if command -v deno >/dev/null 2>&1; then
  deno check "$ROOT_DIR/supabase/functions/enroll-device/index.ts"
  deno check "$ROOT_DIR/supabase/functions/ingest-usage/index.ts"
else
  echo "Deno not installed: skipped Edge Function type-check."
fi

echo "Cloud asset structure verification passed."

