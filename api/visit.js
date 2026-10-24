// Función de Vercel: registra una visita (país/ciudad salen de la conexión; no se guarda la IP).
const SB_URL = "https://otlrgjezfuwlxqigqpfz.supabase.co";
const SB_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im90bHJnamV6ZnV3bHhxaWdxcGZ6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA5NjY5MDEsImV4cCI6MjEwNjU0MjkwMX0.j_eQn8LafoxQ8WeT4OlBrfFTDvZIV8tO4pGylbGKu7k";

const BOT = /bot|crawl|spider|slurp|preview|facebookexternalhit|headless|lighthouse|monitor|curl|wget|python-requests/i;
function dec(v) { try { return decodeURIComponent(String(v || "")).slice(0, 80) || null; } catch { return null; } }
function clean(v, n) { v = String(v || "").trim().slice(0, n || 60); return v || null; }

function sourceOf(utm, ref) {
  if (utm) {
    const u = utm.toLowerCase();
    if (/^(ig|instagram)/.test(u)) return "Instagram";
    if (/^(fb|facebook|meta)/.test(u)) return "Facebook";
    if (/^(wa|whatsapp)/.test(u)) return "WhatsApp";
    if (/^(tt|tiktok)/.test(u)) return "TikTok";
    if (/^(yt|youtube)/.test(u)) return "YouTube";
    if (/google/.test(u)) return "Google";
    return clean(utm, 40);
  }
  if (!ref) return "Directo";
  let h = "";
  try { h = new URL(ref).hostname.replace(/^www\./, "").toLowerCase(); } catch { return "Directo"; }
  if (/instagram\.com$/.test(h)) return "Instagram";
  if (/(facebook|fb)\.com$|fb\.me$|messenger\.com$/.test(h)) return "Facebook";
  if (/whatsapp\.com$|wa\.me$/.test(h)) return "WhatsApp";
  if (/tiktok\.com$/.test(h)) return "TikTok";
  if (/youtube\.com$|youtu\.be$/.test(h)) return "YouTube";
  if (/google\./.test(h)) return "Google";
  if (/(^|\.)t\.co$|twitter\.com$|x\.com$/.test(h)) return "X / Twitter";
  if (/ludmibox|vercel\.app$/.test(h)) return "Directo";
  return h.slice(0, 40);
}

module.exports = async (req, res) => {
  if (req.method !== "POST") { res.status(405).end(); return; }
  try {
    const b = typeof req.body === "string" ? JSON.parse(req.body || "{}") : (req.body || {});
    const ua = String(req.headers["user-agent"] || "");
    if (!ua || BOT.test(ua)) { res.status(204).end(); return; }
    const event = b.event === "chat" ? "chat" : "view";
    const vid = clean(b.vid, 64);
    if (!vid || vid.length < 8) { res.status(400).end(); return; }
    const row = {
      vid, event,
      country: clean(req.headers["x-vercel-ip-country"], 2),
      region: dec(req.headers["x-vercel-ip-country-region"]),
      city: dec(req.headers["x-vercel-ip-city"]),
      source: sourceOf(clean(b.utm_source, 60), clean(b.ref, 300)),
      campaign: clean(b.utm_campaign, 60),
      device: /ipad|tablet/i.test(ua) ? "tablet" : /mobi|android|iphone/i.test(ua) ? "mobile" : "desktop",
    };
    const r = await fetch(SB_URL + "/rest/v1/visits", {
      method: "POST",
      headers: { apikey: SB_KEY, Authorization: "Bearer " + SB_KEY, "Content-Type": "application/json", Prefer: "return=minimal" },
      body: JSON.stringify(row),
    });
    res.status(r.ok ? 204 : 502).end();
  } catch (e) {
    res.status(500).end();
  }
};
