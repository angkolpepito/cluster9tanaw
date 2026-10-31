// Account manager. Env vars (Netlify → Site settings → Environment): SUPABASE_URL, SUPABASE_SERVICE_KEY
//  - no "action": create or reset a school head login (PSDS only)
//  - action create_encoder / update_encoder / delete_encoder: encoder accounts (PSDS for any school, school head for their own school)
const U = process.env.SUPABASE_URL, K = process.env.SUPABASE_SERVICE_KEY;
const J = (c, o) => new Response(JSON.stringify(o), { status: c, headers: { "content-type": "application/json" } });
const api = (p, o = {}) => fetch(U + p, { ...o, headers: { apikey: K, Authorization: "Bearer " + K, "content-type": "application/json", ...(o.headers || {}) } });
// Dashboard tabs that can be assigned to an encoder (must match the sections in tab_modules and the app).
const SECTIONS = ["learners", "personnel", "positions", "pmes", "rates", "academic", "handa", "mooe", "okdeped", "philiri", "aral", "ops", "innov", "ta", "als", "sned", "slac"];
const MAX_ENCODERS = 25;

export default async (req) => {
  try { return await run(req); } catch (e) { return J(500, { error: "Function error: " + (e && e.message || e) }); }
};
const cleanUser = (u) => String(u || "").toLowerCase().replace(/[^a-z0-9._-]/g, "");
const emailOf = (u) => `${u}@cluster9.tanaw.local`;

async function run(req) {
  if (!U || !K) return J(500, { error: "Missing environment variables SUPABASE_URL and/or SUPABASE_SERVICE_KEY. Add them in the host's environment settings, then redeploy." });
  if (req.method !== "POST") return J(405, { error: "POST only" });
  const jwt = (req.headers.get("authorization") || "").replace("Bearer ", "");
  const who = await fetch(U + "/auth/v1/user", { headers: { apikey: K, Authorization: "Bearer " + jwt } }).then(r => r.json());
  if (!who.id) return J(401, { error: "Not signed in" });
  const me = (await api(`/rest/v1/profiles?user_id=eq.${who.id}&select=role,school_id`).then(r => r.json()))[0];
  if (!me) return J(403, { error: "No role for this account" });
  const body = await req.json();

  if (!body.action) {
    if (me.role !== "psds") return J(403, { error: "PSDS only" });
    return headLogin(body);
  }
  if (me.role !== "psds" && me.role !== "school_head") return J(403, { error: "Only the PSDS or a school head can manage encoder accounts" });
  const action = body.action;
  if (action === "create_encoder") return createEncoder(me, body);
  if (action === "update_encoder") return updateEncoder(me, body);
  if (action === "delete_encoder") return deleteEncoder(me, body);
  return J(400, { error: "Unknown action" });
}

async function headLogin({ school_id, username, password, full_name }) {
  if (!school_id || !password || password.length < 8) return J(400, { error: "school_id and a password of 8+ characters are required" });
  const ex = (await api(`/rest/v1/profiles?school_id=eq.${school_id}&role=eq.school_head&select=user_id`).then(r => r.json()))[0];
  if (ex) {
    const r = await api(`/auth/v1/admin/users/${ex.user_id}`, { method: "PUT", body: JSON.stringify({ password }) });
    return r.ok ? J(200, { ok: true, reset: true }) : J(400, await r.json());
  }
  if (!username) return J(400, { error: "username required" });
  const email = emailOf(cleanUser(username));
  const r = await api("/auth/v1/admin/users", { method: "POST", body: JSON.stringify({ email, password, email_confirm: true }) });
  const u = await r.json();
  if (!u.id) return J(400, { error: u.msg || u.message || "Could not create user" });
  await api("/rest/v1/profiles", { method: "POST", body: JSON.stringify({ user_id: u.id, role: "school_head", school_id, full_name: full_name || null, username: email.split("@")[0] }) });
  return J(200, { ok: true, username: email.split("@")[0] });
}

const goodTabs = (t) => Array.isArray(t) && t.length > 0 && t.every(x => SECTIONS.includes(x)) ? [...new Set(t)] : null;

// A school head may only act on their own school; the PSDS names the school.
function schoolFor(me, body) { return me.role === "school_head" ? me.school_id : body.school_id; }

async function targetEncoder(me, body) {
  if (!body.user_id) return null;
  const t = (await api(`/rest/v1/profiles?user_id=eq.${body.user_id}&role=eq.encoder&select=user_id,school_id`).then(r => r.json()))[0];
  if (!t) return null;
  if (me.role === "school_head" && t.school_id !== me.school_id) return null;
  return t;
}

async function createEncoder(me, body) {
  const school_id = schoolFor(me, body), username = cleanUser(body.username), tabs = goodTabs(body.tabs);
  const full_name = String(body.full_name || "").trim();
  if (!school_id) return J(400, { error: "school_id required" });
  const sc = (await api(`/rest/v1/schools?id=eq.${school_id}&select=id`).then(r => r.json()))[0];
  if (!sc) return J(400, { error: "School not found" });
  if (!full_name) return J(400, { error: "Full name required" });
  if (username.length < 3 || username.length > 30) return J(400, { error: "Username must be 3 to 30 characters (letters, numbers, dot, dash, underscore)" });
  if (!body.password || body.password.length < 8) return J(400, { error: "Password of 8+ characters required" });
  if (!tabs) return J(400, { error: "Assign at least one tab" });
  const have = await api(`/rest/v1/profiles?school_id=eq.${school_id}&role=eq.encoder&select=user_id`).then(r => r.json());
  if (have.length >= MAX_ENCODERS) return J(400, { error: `A school can have at most ${MAX_ENCODERS} encoder accounts` });
  const r = await api("/auth/v1/admin/users", { method: "POST", body: JSON.stringify({ email: emailOf(username), password: body.password, email_confirm: true }) });
  const u = await r.json();
  if (!u.id) return J(400, { error: /already|registered|exists/i.test(u.msg || u.message || "") ? "That username is already taken. Choose another." : (u.msg || u.message || "Could not create user") });
  const p = await api("/rest/v1/profiles", { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ user_id: u.id, role: "encoder", school_id, full_name, username, tabs }) });
  if (!p.ok) { await api(`/auth/v1/admin/users/${u.id}`, { method: "DELETE" }); return J(400, { error: "Could not save the profile (has supabase_update_accounts.sql been run?)" }); }
  return J(200, { ok: true, username });
}

async function updateEncoder(me, body) {
  const t = await targetEncoder(me, body);
  if (!t) return J(404, { error: "Encoder not found" });
  const patch = {};
  if (body.full_name !== undefined) { const n = String(body.full_name).trim(); if (!n) return J(400, { error: "Full name required" }); patch.full_name = n; }
  if (body.tabs !== undefined) { const tabs = goodTabs(body.tabs); if (!tabs) return J(400, { error: "Assign at least one tab" }); patch.tabs = tabs; }
  if (body.password) {
    if (body.password.length < 8) return J(400, { error: "Password of 8+ characters required" });
    const r = await api(`/auth/v1/admin/users/${t.user_id}`, { method: "PUT", body: JSON.stringify({ password: body.password }) });
    if (!r.ok) return J(400, await r.json());
  }
  if (Object.keys(patch).length) {
    const r = await api(`/rest/v1/profiles?user_id=eq.${t.user_id}`, { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify(patch) });
    if (!r.ok) return J(400, { error: "Could not save the changes" });
  }
  return J(200, { ok: true });
}

async function deleteEncoder(me, body) {
  const t = await targetEncoder(me, body);
  if (!t) return J(404, { error: "Encoder not found" });
  const r = await api(`/auth/v1/admin/users/${t.user_id}`, { method: "DELETE" });
  return r.ok ? J(200, { ok: true }) : J(400, await r.json());
}
