alter table public.usage_buckets add column hourly_usage jsonb not null default '[]'::jsonb;
alter table public.usage_buckets add constraint hourly_usage_array check (jsonb_typeof(hourly_usage) = 'array');

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
    if position('/' in row_data ->> 'project_name') > 0 or position(chr(92) in row_data ->> 'project_name') > 0 then
      raise exception 'project path rejected';
    end if;
    insert into public.usage_buckets(
      workspace_id, device_id, local_date, timezone, agent_key, agent_name, model, project_key, project_name,
      input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, reasoning_tokens, total_tokens,
      record_count, schema_version, hourly_usage
    ) values (
      target_workspace, requested_device, (row_data ->> 'local_date')::date, row_data ->> 'timezone',
      row_data ->> 'agent_key', row_data ->> 'agent_name', coalesce(row_data ->> 'model', ''),
      coalesce(row_data ->> 'project_key', ''), coalesce(row_data ->> 'project_name', 'Unnamed'),
      (row_data -> 'tokens' ->> 'input_tokens')::bigint, (row_data -> 'tokens' ->> 'output_tokens')::bigint,
      (row_data -> 'tokens' ->> 'cache_read_tokens')::bigint, (row_data -> 'tokens' ->> 'cache_write_tokens')::bigint,
      (row_data -> 'tokens' ->> 'reasoning_tokens')::bigint, (row_data -> 'tokens' ->> 'total_tokens')::bigint,
      (row_data ->> 'record_count')::bigint, (row_data ->> 'schema_version')::integer,
      coalesce(row_data -> 'hourly_usage', '[]'::jsonb)
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


create or replace view public.usage_dashboard with (security_invoker = true) as
select b.workspace_id, b.local_date, b.device_id, d.display_name as device_name, d.os_family, d.os_version,
       d.architecture, b.agent_key, b.agent_name, b.project_key, b.project_name, b.model,
       b.input_tokens, b.output_tokens, b.cache_read_tokens, b.cache_write_tokens,
       b.reasoning_tokens, b.total_tokens, b.record_count, d.last_seen_at, b.hourly_usage
from public.usage_buckets b join public.devices d on d.id = b.device_id;
