import { PGlite } from '@electric-sql/pglite';
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';

const db = new PGlite();
try {
  await db.exec(`
    create role anon; create role authenticated; create role service_role bypassrls;
    create schema auth; create schema extensions;
    create table auth.users (id uuid primary key, email text, raw_user_meta_data jsonb);
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    $$;
    grant usage on schema auth to authenticated;
    grant execute on function auth.uid() to authenticated;
    -- PGlite lacks pgcrypto: substitutes only exercise SQL control flow, never production crypto.
    create function extensions.gen_random_bytes(n int) returns bytea language sql as $$ select decode(repeat('ab', n), 'hex') $$;
    create function extensions.digest(v text, algo text) returns bytea language sql as $$ select convert_to(v, 'UTF8') $$;
  `);
  const migration = await readFile(new URL('../../supabase/migrations/202610060001_initial_cloud_schema.sql', import.meta.url), 'utf8');
  await db.exec(migration.replace('create extension if not exists pgcrypto with schema extensions;', ''));
  const hardening = await readFile(new URL('../../supabase/migrations/20261006233553_cloud_security_hardening.sql', import.meta.url), 'utf8');
  await db.exec(hardening);
  await db.exec(await readFile(new URL('../../supabase/migrations/20261006235908_cloud_hourly_usage.sql', import.meta.url), 'utf8'));
  const user = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  const stranger = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  const device = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
  await db.query(`insert into auth.users values ($1, 'owner@example.test', '{}'), ($2, 'other@example.test', '{}')`, [user, stranger]);
  const workspace = (await db.query(`select workspace_id from public.workspace_members where user_id = $1`, [user])).rows[0].workspace_id;
  await db.query(`select set_config('request.jwt.claim.sub', $1, false)`, [user]);
  const code = (await db.query(`select public.create_device_enrollment_code($1) code`, [workspace])).rows[0].code;
  const descriptor = { device_id: device, display_name: 'Intel Mac', os_family: 'macos', os_version: '14', architecture: 'x86_64', collector_version: 'test' };
  await db.query(`select public.consume_device_enrollment($1, $2::jsonb, 'test-secret-hash')`, [Buffer.from(code).toString('hex'), JSON.stringify(descriptor)]);
  const snapshot = {
    schema_version: 1, generated_at: new Date().toISOString(), timezone: 'Asia/Shanghai', device: descriptor,
    buckets: [{schema_version:1,local_date:new Date().toISOString().slice(0,10),timezone:'Asia/Shanghai',agent_key:'teleagent',agent_name:'TeleAgent',model:'gpt-5',project_key:'p1',project_name:'tokenhub',record_count:1,tokens:{input_tokens:10,output_tokens:4,cache_read_tokens:3,cache_write_tokens:1,reasoning_tokens:2,total_tokens:18}}],
    sources: [{agent_key:'teleagent',state:'ok',files:1,records:1,safe_error:null}]
  };
  const ingest = payload => db.query(`select public.ingest_device_snapshot($1, 'test-secret-hash', $2::jsonb) result`, [device,JSON.stringify(payload)]);
  await ingest(snapshot);
  assert.deepEqual((await db.query('select hourly_usage from public.usage_dashboard')).rows[0].hourly_usage, []);
  snapshot.buckets[0].hourly_usage = [{hour:9,record_count:1,tokens:snapshot.buckets[0].tokens}];
  snapshot.generated_at = new Date(Date.now()+100).toISOString();
  await ingest(snapshot);
  assert.equal((await db.query('select hourly_usage from public.usage_dashboard')).rows[0].hourly_usage[0].tokens.total_tokens,18);
  assert.equal((await db.query('select sum(total_tokens)::int total from public.usage_buckets')).rows[0].total, 18);
  assert.equal((await ingest(snapshot)).rows[0].result.status, 'duplicate_or_older_snapshot');
  await db.exec('set role authenticated');
  assert.equal((await db.query('select * from public.usage_dashboard')).rows.length, 1);
  await db.query(`select set_config('request.jwt.claim.sub', $1, false)`, [stranger]);
  assert.equal((await db.query('select * from public.usage_dashboard')).rows.length, 0);
  await assert.rejects(db.query(`select public.create_device_enrollment_code($1)`, [workspace]), /not authorized/);
  await db.exec('reset role');
  const failed = {...snapshot, generated_at:new Date(Date.now()+1000).toISOString(), buckets:[], sources:[{agent_key:'teleagent',state:'query_failed',files:1,records:0,safe_error:'schema_mismatch'}]};
  await ingest(failed);
  assert.equal((await db.query('select sum(total_tokens)::int total from public.usage_buckets')).rows[0].total,18);
  const invalid = structuredClone(snapshot);
  invalid.generated_at = new Date(Date.now()+2000).toISOString();
  invalid.buckets[0].tokens.total_tokens = -1;
  await assert.rejects(ingest(invalid), /check constraint/);
  assert.equal((await db.query('select sum(total_tokens)::int total from public.usage_buckets')).rows[0].total,18);
  await db.query(`update public.devices set enabled = false where id = $1`, [device]);
  await assert.rejects(ingest({...snapshot,generated_at:new Date(Date.now()+1000).toISOString()}), /unauthorized device/);
  console.log('cloud_sql_ok: migration, enrollment, ingestion, duplicates, RLS, enrollment authorization, source failure retention, transaction rollback, revocation');
} finally {
  await db.close();
}
