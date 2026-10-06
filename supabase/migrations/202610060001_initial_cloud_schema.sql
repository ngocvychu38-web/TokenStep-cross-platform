create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create schema if not exists private;

create table public.workspaces (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 80),
  created_at timestamptz not null default now()
);

create table public.workspace_members (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null default '',
  role text not null default 'member' check (role in ('owner', 'admin', 'member', 'viewer')),
  created_at timestamptz not null default now(),
  primary key (workspace_id, user_id)
);

create table public.devices (
  id uuid primary key,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 120),
  os_family text not null check (os_family in ('macos', 'windows', 'linux', 'unknown')),
  os_version text not null default 'unknown',
  architecture text not null default 'unknown',
  collector_version text not null default 'unknown',
  timezone text not null default 'Asia/Shanghai',
  enabled boolean not null default true,
  last_seen_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table private.device_credentials (
  device_id uuid primary key references public.devices(id) on delete cascade,
  secret_hash text not null,
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  revoked_at timestamptz
);

create table private.enrollment_codes (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  code_hash text not null unique,
  expires_at timestamptz not null,
  created_by uuid references auth.users(id) on delete cascade,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.usage_buckets (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  device_id uuid not null references public.devices(id) on delete cascade,
  local_date date not null,
  timezone text not null,
  agent_key text not null,
  agent_name text not null,
  model text not null default '',
  project_key text not null default '',
  project_name text not null default 'Unnamed',
  input_tokens bigint not null default 0 check (input_tokens >= 0),
  output_tokens bigint not null default 0 check (output_tokens >= 0),
  cache_read_tokens bigint not null default 0 check (cache_read_tokens >= 0),
  cache_write_tokens bigint not null default 0 check (cache_write_tokens >= 0),
  reasoning_tokens bigint not null default 0 check (reasoning_tokens >= 0),
  total_tokens bigint not null check (total_tokens > 0),
  record_count bigint not null default 0 check (record_count >= 0),
  schema_version integer not null,
  updated_at timestamptz not null default now(),
  primary key (device_id, local_date, agent_key, model, project_key)
);

create table public.source_sync_status (
  device_id uuid not null references public.devices(id) on delete cascade,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  agent_key text not null,
  state text not null,
  files bigint not null default 0,
  records bigint not null default 0,
  safe_error text,
  last_attempted_at timestamptz not null default now(),
  last_succeeded_at timestamptz,
  primary key (device_id, agent_key)
);

create table public.ingestion_runs (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  device_id uuid not null references public.devices(id) on delete cascade,
  generated_at timestamptz not null,
  bucket_count integer not null,
  source_count integer not null,
  status text not null default 'accepted',
  created_at timestamptz not null default now()
);

create index usage_buckets_workspace_date_idx on public.usage_buckets(workspace_id, local_date desc);
create index usage_buckets_workspace_agent_date_idx on public.usage_buckets(workspace_id, agent_key, local_date desc);
create index usage_buckets_workspace_project_date_idx on public.usage_buckets(workspace_id, project_key, local_date desc);
create index devices_workspace_idx on public.devices(workspace_id);

create or replace function private.is_workspace_member(target_workspace uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.workspace_members
    where workspace_id = target_workspace and user_id = (select auth.uid())
  );
$$;

create or replace function private.is_workspace_admin(target_workspace uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.workspace_members
    where workspace_id = target_workspace
      and user_id = (select auth.uid())
      and role in ('owner', 'admin')
  );
$$;

alter table public.workspaces enable row level security;
alter table public.workspace_members enable row level security;
alter table public.devices enable row level security;
alter table public.usage_buckets enable row level security;
alter table public.source_sync_status enable row level security;
alter table public.ingestion_runs enable row level security;

create policy workspaces_select on public.workspaces for select to authenticated
  using (private.is_workspace_member(id));
create policy members_select on public.workspace_members for select to authenticated
  using (private.is_workspace_member(workspace_id));
create policy devices_select on public.devices for select to authenticated
  using (private.is_workspace_member(workspace_id));
create policy usage_select on public.usage_buckets for select to authenticated
  using (private.is_workspace_member(workspace_id));
create policy source_status_select on public.source_sync_status for select to authenticated
  using (private.is_workspace_member(workspace_id));
create policy ingestion_runs_select on public.ingestion_runs for select to authenticated
  using (private.is_workspace_member(workspace_id));

revoke all on all tables in schema public from anon;
revoke insert, update, delete on public.workspaces, public.workspace_members, public.devices,
  public.usage_buckets, public.source_sync_status, public.ingestion_runs from authenticated;
grant select on public.workspaces, public.workspace_members, public.devices,
  public.usage_buckets, public.source_sync_status, public.ingestion_runs to authenticated;

create or replace function public.handle_new_tokenstep_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  new_workspace uuid;
begin
  insert into public.workspaces(name)
  values (coalesce(nullif(new.raw_user_meta_data ->> 'name', ''), split_part(new.email, '@', 1), 'TokenStep') || '''s workspace')
  returning id into new_workspace;
  insert into public.workspace_members(workspace_id, user_id, display_name, role)
  values (new_workspace, new.id, coalesce(new.raw_user_meta_data ->> 'name', split_part(new.email, '@', 1), ''), 'owner');
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_tokenstep_user();

create or replace function public.create_device_enrollment_code(target_workspace uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare
  plain_code text := encode(extensions.gen_random_bytes(18), 'hex');
begin
  if not (session_user = 'postgres' and current_setting('role') = 'none')
     and not private.is_workspace_admin(target_workspace) then
    raise exception 'not authorized';
  end if;
  insert into private.enrollment_codes(workspace_id, code_hash, expires_at, created_by)
  values (target_workspace, encode(extensions.digest(plain_code, 'sha256'), 'hex'), now() + interval '10 minutes', auth.uid());
  return plain_code;
end;
$$;

revoke all on function public.create_device_enrollment_code(uuid) from public, anon;
grant execute on function public.create_device_enrollment_code(uuid) to authenticated;

create or replace function public.consume_device_enrollment(
  code_sha256 text,
  device_payload jsonb,
  secret_sha256 text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  enrollment private.enrollment_codes%rowtype;
  requested_device uuid;
begin
  select * into enrollment from private.enrollment_codes
  where code_hash = code_sha256 and consumed_at is null and expires_at > now()
  for update;
  if enrollment.id is null then raise exception 'invalid enrollment code'; end if;
  requested_device := (device_payload ->> 'device_id')::uuid;
  insert into public.devices(id, workspace_id, display_name, os_family, os_version, architecture, collector_version, timezone)
  values (
    requested_device, enrollment.workspace_id, left(device_payload ->> 'display_name', 120),
    coalesce(device_payload ->> 'os_family', 'unknown'), coalesce(device_payload ->> 'os_version', 'unknown'),
    coalesce(device_payload ->> 'architecture', 'unknown'), coalesce(device_payload ->> 'collector_version', 'unknown'),
    coalesce(device_payload ->> 'timezone', 'Asia/Shanghai')
  );
  insert into private.device_credentials(device_id, secret_hash) values (requested_device, secret_sha256);
  update private.enrollment_codes set consumed_at = now() where id = enrollment.id;
  return jsonb_build_object('device_id', requested_device, 'workspace_id', enrollment.workspace_id);
end;
$$;

create or replace function public.ingest_device_snapshot(
  requested_device uuid,
  secret_sha256 text,
  snapshot jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  target_workspace uuid;
  row_data jsonb;
  source_data jsonb;
  min_day date;
  max_day date;
  accepted integer := jsonb_array_length(coalesce(snapshot -> 'buckets', '[]'::jsonb));
begin
  select d.workspace_id into target_workspace
  from public.devices d join private.device_credentials c on c.device_id = d.id
  where d.id = requested_device and d.enabled and c.revoked_at is null and c.secret_hash = secret_sha256
  for update of d;
  if target_workspace is null then raise exception 'unauthorized device'; end if;
  if snapshot -> 'device' ->> 'device_id' <> requested_device::text then raise exception 'device mismatch'; end if;
  if (snapshot ->> 'schema_version')::integer <> 1 then raise exception 'unsupported schema'; end if;
  if accepted > 10000 then raise exception 'too many buckets'; end if;
  if exists (select 1 from public.ingestion_runs where device_id = requested_device
    and generated_at >= (snapshot ->> 'generated_at')::timestamptz) then
    return jsonb_build_object('accepted', 0, 'status', 'duplicate_or_older_snapshot');
  end if;

  select min((item ->> 'local_date')::date), max((item ->> 'local_date')::date)
    into min_day, max_day from jsonb_array_elements(coalesce(snapshot -> 'buckets', '[]'::jsonb)) item;
  if min_day is not null and (min_day < date '2020-01-01' or max_day > current_date + 1) then
    raise exception 'date range rejected';
  end if;

  update public.devices set
    display_name = left(snapshot -> 'device' ->> 'display_name', 120),
    os_family = snapshot -> 'device' ->> 'os_family', os_version = snapshot -> 'device' ->> 'os_version',
    architecture = snapshot -> 'device' ->> 'architecture', collector_version = snapshot -> 'device' ->> 'collector_version',
    timezone = snapshot ->> 'timezone', last_seen_at = now(), updated_at = now()
  where id = requested_device;

  if min_day is not null then
    delete from public.usage_buckets b where b.device_id = requested_device and b.local_date between min_day and max_day
      and b.agent_key in (
        select s ->> 'agent_key' from jsonb_array_elements(snapshot -> 'sources') s
        where s ->> 'state' = 'ok'
      );
  end if;
  for row_data in select * from jsonb_array_elements(coalesce(snapshot -> 'buckets', '[]'::jsonb)) loop
    if not exists (select 1 from jsonb_array_elements(snapshot -> 'sources') s
      where s ->> 'agent_key' = row_data ->> 'agent_key' and s ->> 'state' = 'ok') then
      continue;
    end if;
    if position('/' in row_data ->> 'project_name') > 0 or position('\\' in row_data ->> 'project_name') > 0 then
      raise exception 'project path rejected';
    end if;
    insert into public.usage_buckets(
      workspace_id, device_id, local_date, timezone, agent_key, agent_name, model, project_key, project_name,
      input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, reasoning_tokens, total_tokens,
      record_count, schema_version
    ) values (
      target_workspace, requested_device, (row_data ->> 'local_date')::date, row_data ->> 'timezone',
      row_data ->> 'agent_key', row_data ->> 'agent_name', coalesce(row_data ->> 'model', ''),
      coalesce(row_data ->> 'project_key', ''), coalesce(row_data ->> 'project_name', 'Unnamed'),
      (row_data -> 'tokens' ->> 'input_tokens')::bigint, (row_data -> 'tokens' ->> 'output_tokens')::bigint,
      (row_data -> 'tokens' ->> 'cache_read_tokens')::bigint, (row_data -> 'tokens' ->> 'cache_write_tokens')::bigint,
      (row_data -> 'tokens' ->> 'reasoning_tokens')::bigint, (row_data -> 'tokens' ->> 'total_tokens')::bigint,
      (row_data ->> 'record_count')::bigint, (row_data ->> 'schema_version')::integer
    );
  end loop;

  for source_data in select * from jsonb_array_elements(coalesce(snapshot -> 'sources', '[]'::jsonb)) loop
    insert into public.source_sync_status(device_id, workspace_id, agent_key, state, files, records, safe_error, last_succeeded_at)
    values (requested_device, target_workspace, source_data ->> 'agent_key', source_data ->> 'state',
      (source_data ->> 'files')::bigint, (source_data ->> 'records')::bigint, source_data ->> 'safe_error',
      case when source_data ->> 'state' = 'ok' then now() else null end)
    on conflict (device_id, agent_key) do update set
      state = excluded.state, files = excluded.files, records = excluded.records, safe_error = excluded.safe_error,
      last_attempted_at = now(), last_succeeded_at = coalesce(excluded.last_succeeded_at, public.source_sync_status.last_succeeded_at);
  end loop;
  update private.device_credentials set last_used_at = now() where device_id = requested_device;
  insert into public.ingestion_runs(workspace_id, device_id, generated_at, bucket_count, source_count)
  values (target_workspace, requested_device, (snapshot ->> 'generated_at')::timestamptz, accepted,
    jsonb_array_length(coalesce(snapshot -> 'sources', '[]'::jsonb)));
  return jsonb_build_object('accepted', accepted, 'device_id', requested_device, 'received_at', now());
end;
$$;

revoke all on function public.consume_device_enrollment(text, jsonb, text) from public, anon, authenticated;
revoke all on function public.ingest_device_snapshot(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.consume_device_enrollment(text, jsonb, text) to service_role;
grant execute on function public.ingest_device_snapshot(uuid, text, jsonb) to service_role;

create or replace view public.usage_dashboard with (security_invoker = true) as
select b.workspace_id, b.local_date, b.device_id, d.display_name as device_name, d.os_family, d.os_version,
       d.architecture, b.agent_key, b.agent_name, b.project_key, b.project_name, b.model,
       b.input_tokens, b.output_tokens, b.cache_read_tokens, b.cache_write_tokens,
       b.reasoning_tokens, b.total_tokens, b.record_count, d.last_seen_at
from public.usage_buckets b join public.devices d on d.id = b.device_id;

grant select on public.usage_dashboard to authenticated;
grant usage on schema private to authenticated;
grant execute on function private.is_workspace_member(uuid) to authenticated;
grant execute on function private.is_workspace_admin(uuid) to authenticated;
