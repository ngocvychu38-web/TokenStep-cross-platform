import { createClient } from "npm:@supabase/supabase-js@2.117.2";
import { corsHeaders, json, sha256 } from "../_shared/http.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return json({ error: "missing_device_token" }, 401);
  try {
    const snapshot = await request.json();
    const deviceId = String(snapshot?.device?.device_id ?? "");
    if (!deviceId || !Array.isArray(snapshot?.buckets) || snapshot.buckets.length > 10000) {
      return json({ error: "invalid_snapshot" }, 400);
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
    if (error) return json({ error: "ingestion_rejected" }, 401);
    return json(data, 200);
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
});
