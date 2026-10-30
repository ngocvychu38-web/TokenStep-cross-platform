import { createClient } from "npm:@supabase/supabase-js@2.117.2";
import { corsHeaders, json, sha256 } from "../_shared/http.ts";

Deno.serve(async (request) => {
  const requestId = crypto.randomUUID();
  const started = Date.now();
  const reply = (body: unknown, status: number) => {
    const response = json(body, status);
    response.headers.set("x-tokenstep-request-id", requestId);
    console.log(JSON.stringify({ event: "ingest_response", request_id: requestId, status, elapsed_ms: Date.now() - started }));
    return response;
  };
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return reply({ error: "method_not_allowed" }, 405);
  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return reply({ error: "missing_device_token" }, 401);
  try {
    const snapshot = await request.json();
    const deviceId = String(snapshot?.device?.device_id ?? "");
    if (!deviceId || !Array.isArray(snapshot?.buckets) || snapshot.buckets.length > 10000) {
      return reply({ error: "invalid_snapshot" }, 400);
    }
    const client = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );
    const { data, error } = await client.rpc("ingest_device_snapshot", {
      requested_device: deviceId,
      secret_sha256: await sha256(authorization.slice(7)),
      snapshot,
    });
    if (error) return reply({ error: "ingestion_rejected" }, 401);
    console.log(JSON.stringify({ event: "ingest_ok", request_id: requestId, device_id: deviceId,
      buckets: snapshot.buckets.length, accepted: data?.accepted, duplicate: data?.duplicate ?? false }));
    return reply(data, 200);
  } catch {
    return reply({ error: "invalid_json" }, 400);
  }
});
