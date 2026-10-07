import { createClient } from "npm:@supabase/supabase-js@2.117.2";
import { corsHeaders, json, sha256 } from "../_shared/http.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const body = await request.json();
    const enrollmentCode = String(body.enrollment_code ?? "");
    const device = body.device ?? {};
    if (enrollmentCode.length < 20 || !device.device_id || !device.display_name) {
      return json({ error: "invalid_request" }, 400);
    }
    const deviceSecret = crypto.randomUUID() + crypto.randomUUID();
    const client = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );
    const { data, error } = await client.rpc("consume_device_enrollment", {
      code_sha256: await sha256(enrollmentCode),
      device_payload: device,
      secret_sha256: await sha256(deviceSecret),
    });
    if (error) return json({ error: "enrollment_rejected" }, 401);
    return json({ ...data, device_token: deviceSecret }, 201);
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
});
