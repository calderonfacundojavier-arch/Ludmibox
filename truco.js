// API del Truco (Vercel). Una sola función: POST /api/truco {action, ...}
// El servidor es la única autoridad: reparte con aleatoriedad criptográfica, valida cada jugada,
// y es el único que mueve dinero. El navegador solo recibe SU vista (nunca las cartas del rival).
const crypto = require("crypto");
const T = require("../lib/truco-engine.js");

const URL_ = (process.env.SUPABASE_URL || "").replace(/\/$/, "");
const SVC = process.env.SUPABASE_SERVICE_ROLE_KEY || "";
const DOMAIN = process.env.TRUCO_EMAIL_DOMAIN || "truco-jugadores.com";
const rng = () => crypto.randomInt(0, 2 ** 32) / 2 ** 32;

class Err extends Error { constructor(m, code) { super(m); this.code = code || 400; } }
// Claves nuevas (sb_secret_...) van solo en "apikey"; las clásicas (eyJ...) también como Bearer.
const H = (extra) => Object.assign({ apikey: SVC, "Content-Type": "application/json" }, SVC.startsWith("eyJ") ? { Authorization: "Bearer " + SVC } : {}, extra || {});

async function http(url, opt) {
  const r = await fetch(url, opt);
  const txt = await r.text();
  let j = null; try { j = txt ? JSON.parse(txt) : null; } catch (_) {}
  if (!r.ok) throw new Err((j && (j.message || j.msg || j.error_description || j.error)) || "Error del servidor", r.status === 401 ? 401 : 400);
  return j;
}
const rpc = (name, args) => http(`${URL_}/rest/v1/rpc/${name}`, { method: "POST", headers: H(), body: JSON.stringify(args || {}) });
const select = (path) => http(`${URL_}/rest/v1/${path}`, { headers: H() });

const emailOf = (u) => `${u.toLowerCase()}@${DOMAIN}`;
const okUser = (u) => /^[a-zA-Z0-9_]{3,20}$/.test(u || "");

async function login(username, password) {
  if (!okUser(username)) throw new Err("Usuario o contraseña incorrectos.");
  const r = await fetch(`${URL_}/auth/v1/token?grant_type=password`, { method: "POST", headers: H(), body: JSON.stringify({ email: emailOf(username), password }) });
  const j = await r.json().catch(() => ({}));
  if (!r.ok || !j.access_token) throw new Err("Usuario o contraseña incorrectos.", 401);
  return { access_token: j.access_token, refresh_token: j.refresh_token };
}

const authCache = new Map(); // token -> {uid, exp}: evita un viaje a Supabase en cada jugada
async function authUser(req) {
  const tok = String(req.headers.authorization || "").replace(/^Bearer\s+/i, "");
  if (!tok) throw new Err("Iniciá sesión.", 401);
  const c = authCache.get(tok);
  if (c && c.exp > Date.now()) return c.uid;
  const r = await fetch(`${URL_}/auth/v1/user`, { headers: { apikey: SVC, Authorization: "Bearer " + tok } });
  if (!r.ok) throw new Err("Sesión vencida. Ingresá de nuevo.", 401);
  const u = await r.json();
  if (authCache.size > 500) authCache.clear();
  authCache.set(tok, { uid: u.id, exp: Date.now() + 60000 });
  return u.id;
}

let SC = { at: 0, v: null };
async function settings(force) {
  if (!force && SC.v && Date.now() - SC.at < 30000) return SC.v;
  SC = { at: Date.now(), v: (await select("t_settings?id=eq.1&select=*"))[0] };
  return SC.v;
}
async function me(id) { return rpc("t_me", { p_id: id }); }

/* Una mesa en memoria: {t: fila de t_tables, n0, n1, moveSecs}. Se carga con UNA consulta. */
async function load(id) {
  if (!/^[0-9a-f-]{36}$/i.test(id || "")) throw new Err("Mesa inválida.");
  const r = await rpc("t_load", { p_table: id });
  if (!r || !r.t) throw new Err("La mesa no existe.", 404);
  return { t: r.t, n0: r.n0, n1: r.n1, moveSecs: r.move_secs };
}
const slotOf = (t, uid) => (t.p0 === uid ? 0 : t.p1 === uid ? 1 : -1);

function initState(t) {
  return T.newGame({ target: t.target, flor: t.flor, mano: rng() < 0.5 ? 0 : 1 }, rng);
}
/* quién debe actuar ahora (null si nadie) */
const actor = (st) => [0, 1].find((q) => T.legalActions(st, q).length) ?? null;

/* la máquina juega hasta que le toque a una persona */
function runBot(st, skill) {
  let guard = 0;
  while (!st.over && guard++ < 60) {
    const p = actor(st);
    if (p !== 1) break;
    const a = T.botAct(T.view(st, 1), rng, skill == null ? 100 : skill);
    if (!a) break;
    st = T.act(st, 1, a, rng);
  }
  return st;
}

async function ensureState(c) {
  const t = c.t;
  if (t.state || t.status !== "playing") return c;
  let st = initState(t);
  if (t.vs_bot) st = runBot(st, t.bot_skill);
  const row = await rpc("t_set_state", { p_table: t.id, p_seq: t.seq, p_state: st });
  if (row) { c.t = row; return c; }
  return load(t.id); // otro pedido la inicializó primero
}

function payload(c, uid) {
  const t = c.t, slot = slotOf(t, uid);
  const out = {
    table: t.id, status: t.status, stake: Number(t.stake), vsBot: t.vs_bot,
    pot: t.vs_bot ? (t.bot_payout ? Number(t.stake) * Number(t.bot_payout) : 0) : Number(t.stake) * 2,
    rakePct: t.vs_bot ? 0 : Number(t.rake_pct), payout: t.bot_payout ? Number(t.bot_payout) : null,
    slot, names: [c.n0 || "?", t.vs_bot ? "Máquina" : c.n1 || "?"], seq: t.seq, target: t.target, moveSecs: c.moveSecs,
    lastMoveAt: t.last_move_at, serverNow: new Date().toISOString(),
  };
  if (t.status === "finished") {
    out.winnerSlot = t.winner ? (t.winner === t.p0 ? 0 : 1) : (t.vs_bot ? 1 : null);
    out.reason = t.win_reason;
    out.prize = t.winner === uid ? Number(t.pot) - Number(t.rake) : 0;
    out.pot = Number(t.pot) || out.pot;
    out.rake = Number(t.rake);
  }
  if (t.state) {
    out.view = T.view(t.state, slot);
    out.whoActs = t.status === "playing" ? actor(t.state) : null;
  }
  return out;
}

/* aplica una jugada con bloqueo optimista; paga si terminó (2-3 consultas en total) */
async function applyMove(tableId, uid, action) {
  for (let tries = 0; tries < 4; tries++) {
    let c = await load(tableId);
    const slot = slotOf(c.t, uid);
    if (slot < 0) throw new Err("No sos parte de esta mesa.", 403);
    if (c.t.status !== "playing") throw new Err("La mesa no está en juego.");
    c = await ensureState(c);
    let st;
    try { st = T.act(c.t.state, slot, action, rng); } catch (e) { throw new Err(e.message); }
    if (c.t.vs_bot) st = runBot(st, c.t.bot_skill);
    const row = await rpc("t_set_state", { p_table: c.t.id, p_seq: c.t.seq, p_state: st });
    if (!row) continue; // alguien movió en el medio: reintento
    c.t = row;
    if (st.over) c.t = (await rpc("t_settle", { p_table: c.t.id, p_slot: st.winner, p_reason: "cartas", p_state: st })) || c.t;
    return c;
  }
  throw new Err("La mesa cambió, probá de nuevo.");
}

async function mkAuth(u, pw) {
  try { return await http(`${URL_}/auth/v1/admin/users`, { method: "POST", headers: H(), body: JSON.stringify({ email: emailOf(u), password: pw, email_confirm: true }) }); }
  catch (e) { throw new Err(/already|registered|exists/i.test(e.message) ? "Ese usuario ya existe." : e.message); }
}
const delAuth = (id) => fetch(`${URL_}/auth/v1/admin/users/${id}`, { method: "DELETE", headers: H() }).catch(() => {});
const num = (v) => { const n = Number(v); return Number.isFinite(n) ? n : 0; };
const isoOr = (v) => (v && !isNaN(Date.parse(v)) ? new Date(v).toISOString() : null);

/* ---------- panel de agentes ---------- */
async function panel(a, uid, b) {
  const m = await me(uid);
  if (!m || m.role === "player") throw new Err("Esta cuenta es de jugador: ingresá al juego.", 403);
  if (m.blocked) throw new Err("Tu cuenta está bloqueada.", 403);
  if (a === "p_me") return { me: m };
  if (a === "p_users") return rpc("t_list_users", { p_actor: uid, p_q: String(b.q || "").slice(0, 40), p_group: ["all", "players", "agents", "blocked"].includes(b.group) ? b.group : "all",
    p_blocked: typeof b.blocked === "boolean" ? b.blocked : null, p_parent: String(b.parent || "").slice(0, 20), p_limit: Math.min(200, num(b.limit) || 25), p_offset: Math.max(0, num(b.offset)) });
  if (a === "p_tree") return { rows: await rpc("t_tree", { p_actor: uid }) };
  if (a === "p_create") {
    const u = String(b.username || "").trim(), pw = String(b.password || "");
    if (!okUser(u)) throw new Err("El usuario debe tener de 3 a 20 letras, números o _.");
    if (pw.length < 6) throw new Err("La contraseña debe tener al menos 6 caracteres.");
    const role = String(b.role || "");
    if (!["platform", "agent", "player"].includes(role)) throw new Err("Elegí el tipo de usuario.");
    const initial = Math.max(0, num(b.credits));
    const created = await mkAuth(u, pw);
    try {
      await rpc("t_create_user", { p_actor: uid, p_id: created.id, p_username: u, p_role: role, p_commission: num(b.commission), p_price: b.price === undefined || b.price === "" ? null : num(b.price),
        p_phone: String(b.phone || ""), p_note: String(b.note || ""), p_initial: initial });
    } catch (e) { await delAuth(created.id); throw new Err(/duplicate|unique/i.test(e.message) ? "Ese usuario ya existe." : e.message); }
    return { ok: true };
  }
  if (a === "p_transfer") return rpc("t_transfer", { p_actor: uid, p_username: String(b.username || ""), p_kind: String(b.kind || ""), p_amount: num(b.amount), p_note: String(b.note || "") });
  if (a === "p_update") { await rpc("t_update_user", { p_actor: uid, p_username: String(b.username || ""), p_set: b.set || {} }); return { ok: true }; }
  if (a === "p_setpass") {
    const pw = String(b.password || "");
    if (pw.length < 6) throw new Err("La contraseña debe tener al menos 6 caracteres.");
    const rid = await rpc("t_user_id", { p_username: String(b.username || "") });
    if (!rid) throw new Err("No existe ese usuario.");
    if (rid !== uid && !(await rpc("t_manages", { p_actor: uid, p_target: rid }))) throw new Err("No podés cambiar esa contraseña.", 403);
    await http(`${URL_}/auth/v1/admin/users/${rid}`, { method: "PUT", headers: H(), body: JSON.stringify({ password: pw }) });
    return { ok: true };
  }
  if (a === "p_tx") return rpc("t_tx_list", { p_actor: uid, p_user: String(b.user || ""), p_kind: String(b.kind || ""), p_from: isoOr(b.from), p_to: isoOr(b.to), p_limit: Math.min(300, num(b.limit) || 50), p_offset: Math.max(0, num(b.offset)) });
  if (a === "p_tables") return { rows: await rpc("t_tables_list", { p_actor: uid, p_limit: 80 }) };
  if (a === "p_sales") return rpc("t_sales_list", { p_actor: uid, p_limit: 200 });
  if (a === "p_report") return rpc("t_report", { p_actor: uid, p_from: isoOr(b.from) || new Date(Date.now() - 864e5).toISOString(), p_to: isoOr(b.to) || new Date(Date.now() + 864e5).toISOString() });
  if (a === "p_settings") {
    if (b.set) { const r = await rpc("t_update_settings", { p_actor: uid, p_set: b.set }); SC = { at: 0, v: null }; return r; }
    return settings(true);
  }
  if (a === "p_mint") return { balance: await rpc("t_mint", { p_actor: uid, p_amount: num(b.amount), p_note: String(b.note || "") }) };
  if (a === "p_bot") {
    if (b.set) return rpc("t_set_bot", { p_actor: uid, p_username: String(b.username || m.username), p_set: b.set });
    return rpc("t_bot_info", { p_actor: uid });
  }
  throw new Err("Acción desconocida.");
}

async function handle(req, b) {
  const a = b.action;
  if (!URL_ || !SVC) throw new Err("Falta configurar el servidor (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY).", 500);

  if (a === "refresh") {
    const r = await fetch(`${URL_}/auth/v1/token?grant_type=refresh_token`, { method: "POST", headers: H(), body: JSON.stringify({ refresh_token: String(b.refresh_token || "") }) });
    const j = await r.json().catch(() => ({}));
    if (!r.ok || !j.access_token) throw new Err("Sesión vencida. Ingresá de nuevo.", 401);
    return { access_token: j.access_token, refresh_token: j.refresh_token };
  }
  if (a === "login") return login(String(b.username || ""), String(b.password || ""));
  if (a === "setup") {
    // Crea al usuario PADRE una sola vez. Requiere TRUCO_SETUP_KEY en Vercel.
    const key = process.env.TRUCO_SETUP_KEY || "";
    if (!key || String(b.key || "") !== key) throw new Err("Clave de instalación incorrecta.", 403);
    const u = String(b.username || "").trim(), pw = String(b.password || "");
    if (!okUser(u)) throw new Err("El usuario debe tener de 3 a 20 letras, números o _.");
    if (pw.length < 8) throw new Err("La contraseña debe tener al menos 8 caracteres.");
    const ex = await select("t_users?role=eq.root&select=id&limit=1");
    if (ex.length) throw new Err("Ya existe el usuario padre.", 403);
    const created = await mkAuth(u, pw);
    try { await rpc("t_boot_root", { p_id: created.id, p_username: u }); }
    catch (e) { await delAuth(created.id); throw new Err(e.message); }
    return login(u, pw);
  }

  const uid = await authUser(req);

  if (a.startsWith("p_")) return panel(a, uid, b);

  if (a === "me") {
    const p = await me(uid);
    if (!p) throw new Err("Tu cuenta no está habilitada.", 403);
    const s = await settings();
    const base = { username: p.username, role: p.role, balance: Number(p.balance), held: Number(p.held), blocked: p.blocked, parent: p.parent };
    if (p.role !== "player") return base;
    const [act, cfg] = await Promise.all([
      select(`t_tables?status=in.(waiting,playing)&or=(p0.eq.${uid},p1.eq.${uid})&select=id,status,stake,vs_bot&limit=1`),
      rpc("t_bot_cfg", { p_player: uid }),
    ]);
    return Object.assign(base, { active: act[0] || null,
      settings: { minStake: Number(s.min_stake), maxStake: Number(s.max_stake), rakePct: Number(s.rake_pct), botMaxStake: Number(cfg.max_stake), botPayout: Number(cfg.payout),
        moveSecs: s.move_secs, target: s.target, flor: s.flor, maintenance: s.maintenance } });
  }
  if (a === "lobby") {
    const p = await me(uid);
    if (!p || p.role !== "player" || !p.platform_id) throw new Err("Esta cuenta no juega.", 403);
    const rows = await select(`t_pub?status=eq.waiting&vs_bot=eq.false&platform_id=eq.${p.platform_id}&order=updated_at.desc&limit=30&select=id,stake,p0_name,updated_at`);
    return { tables: rows.map((r) => ({ id: r.id, stake: Number(r.stake), by: r.p0_name })) };
  }
  if (a === "history") {
    const rows = await select(`t_tx?user_id=eq.${uid}&order=ts.desc&limit=25&select=ts,kind,amount,note`);
    return { rows: rows.map((r) => ({ ts: r.ts, kind: r.kind, amount: Number(r.amount), note: r.note })) };
  }
  if (a === "create") {
    const id = await rpc("t_create_table", { p_player: uid, p_stake: Number(b.stake) || 0, p_vs_bot: !!b.vsBot, p_mano: 0 });
    let c = await load(id);
    if (c.t.vs_bot) c = await ensureState(c);
    return payload(c, uid);
  }
  if (a === "join") {
    await rpc("t_join_table", { p_table: String(b.table || ""), p_player: uid });
    return payload(await ensureState(await load(String(b.table))), uid);
  }
  if (a === "cancel") { await rpc("t_cancel_table", { p_table: String(b.table || ""), p_player: uid }); return { ok: true }; }

  if (a === "state") {
    const id = String(b.table || "");
    if (b.since != null && /^[0-9a-f-]{36}$/i.test(id)) { // consulta liviana: ¿cambió algo?
      const r = (await select(`t_tables?id=eq.${id}&select=seq,status,p0,p1`))[0];
      if (!r) throw new Err("La mesa no existe.", 404);
      if (slotOf(r, uid) < 0) throw new Err("No sos parte de esta mesa.", 403);
      if (r.seq === Number(b.since) && r.status === b.status) return { same: true, serverNow: new Date().toISOString() };
    }
    let c = await load(id);
    if (slotOf(c.t, uid) < 0) throw new Err("No sos parte de esta mesa.", 403);
    if (c.t.status === "playing") c = await ensureState(c);
    return payload(c, uid);
  }
  if (a === "move") return payload(await applyMove(String(b.table || ""), uid, b.move || {}), uid);

  if (a === "claim" || a === "forfeit") {
    let c = await load(String(b.table || ""));
    const slot = slotOf(c.t, uid);
    if (slot < 0) throw new Err("No sos parte de esta mesa.", 403);
    if (c.t.status !== "playing") return payload(c, uid);
    c = await ensureState(c);
    const t = c.t;
    if (a === "forfeit") {
      c.t = (await rpc("t_settle", { p_table: t.id, p_slot: t.vs_bot ? 1 : 1 - slot, p_reason: "abandono" })) || t;
    } else {
      if (t.vs_bot) throw new Err("Contra la máquina no hay reclamo por tiempo.");
      const owes = actor(t.state);
      const late = (Date.now() - new Date(t.last_move_at).getTime()) / 1000 > c.moveSecs;
      if (owes === null || owes === slot) throw new Err("Es tu turno de jugar.");
      if (!late) throw new Err("Todavía le queda tiempo al rival.");
      c.t = (await rpc("t_settle", { p_table: t.id, p_slot: slot, p_reason: "tiempo" })) || t;
    }
    return payload(c, uid);
  }
  throw new Err("Acción desconocida.");
}

module.exports = async (req, res) => {
  res.setHeader("Cache-Control", "no-store");
  if (req.method !== "POST") { res.status(405).json({ error: "POST" }); return; }
  try {
    const b = typeof req.body === "string" ? JSON.parse(req.body || "{}") : req.body || {};
    res.status(200).json(await handle(req, b));
  } catch (e) {
    const code = e instanceof Err ? e.code : 500;
    res.status(code).json({ error: e instanceof Err ? e.message : "Error interno" });
  }
};
module.exports._test = { handle, applyMove, runBot, actor };
