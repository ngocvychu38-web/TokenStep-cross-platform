-- Trigger-only function is not a public RPC. Existing trigger keeps working.
revoke all on function public.handle_new_tokenstep_user() from public, anon, authenticated;
revoke all on function private.is_workspace_member(uuid) from public, anon;
revoke all on function private.is_workspace_admin(uuid) from public, anon;
revoke all on all tables in schema private from anon, authenticated;
alter table private.device_credentials enable row level security;
alter table private.enrollment_codes enable row level security;

create index workspace_members_user_id_idx on public.workspace_members(user_id);
create index enrollment_codes_created_by_idx on private.enrollment_codes(created_by);
create index enrollment_codes_workspace_idx on private.enrollment_codes(workspace_id);
create index ingestion_runs_device_generated_idx on public.ingestion_runs(device_id, generated_at desc);
create index ingestion_runs_workspace_idx on public.ingestion_runs(workspace_id);
create index source_sync_status_workspace_idx on public.source_sync_status(workspace_id);
