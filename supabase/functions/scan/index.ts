// Supabase Edge Function "scan": liest Vokabelpaare aus einem Foto.
// Der Anthropic-API-Key bleibt hier auf dem Server (Secret ANTHROPIC_API_KEY) und ist nie im Browser sichtbar.
// Nur angemeldete Nutzer der App dürfen die Funktion aufrufen.

import { createClient } from "jsr:@supabase/supabase-js@2";

const MODEL = "claude-sonnet-5-5"; // günstiger, etwas ungenauer: "claude-haiku-5-5"
const MAX_IMAGE_BYTES = 5_000_000;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Nur POST erlaubt" }, 405);

  // 1) Angemeldeten Nutzer prüfen
  const authHeader = req.headers.get("Authorization") ?? "";
  const sb = createClient(
    Deno.env.get("SUPABASE_URL") ?? "https://xhbocgunjbrnyrzjsysx.supabase.co",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "sb_publishable_hg0dmW8eAhQyHMt8Vuhufw_4MvX6dCQ", {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user } } = await sb.auth.getUser(authHeader.replace(/^Bearer\s+/i, ""));
  if (!user) return json({ error: "Bitte neu anmelden." }, 401);

  // 2) Eingabe prüfen
  let body: { image?: string; mediaType?: string; from?: string; to?: string };
  try { body = await req.json(); } catch { return json({ error: "Ungültige Anfrage." }, 400); }
  const { image, mediaType = "image/jpeg", from = "Englisch", to = "Deutsch" } = body;
  if (!image || typeof image !== "string") return json({ error: "Kein Bild empfangen." }, 400);
  if (image.length * 0.75 > MAX_IMAGE_BYTES) return json({ error: "Foto ist zu groß." }, 413);
  if (!["image/jpeg", "image/png", "image/webp"].includes(mediaType)) return json({ error: "Bildformat nicht unterstützt." }, 400);

  const key = Deno.env.get("ANTHROPIC_API_KEY");
  if (!key) return json({ error: "API-Key fehlt auf dem Server (Secret ANTHROPIC_API_KEY)." }, 500);

  const prompt = `Das Bild ist ein Foto einer Vokabelliste aus einem Schulbuch oder Vokabelheft. Sie hat zwei Spalten: links ${from}, rechts ${to}.
Extrahiere JEDES Vokabelpaar in der Reihenfolge der Seite.
Regeln:
- "term" = Eintrag der ${from}-Spalte, "definition" = Eintrag der ${to}-Spalte, jeweils wörtlich wie gedruckt (inkl. Artikel, "to ...", Zusätzen wie "(pl.)" oder "jdn./etw.").
- Mehrere Übersetzungen in einer Zelle mit ", " trennen.
- Lautschrift, Seitenzahlen, Überschriften, Lektionstitel und Beispielsätze weglassen, sofern sie nicht Teil der Übersetzung sind.
- Nichts erfinden. Unleserliche Paare weglassen.
Antworte ausschließlich mit JSON ohne weiteren Text: {"pairs":[{"term":"...","definition":"..."}]}`;

  // 3) Claude aufrufen
  const r = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 8000,
      messages: [{
        role: "user",
        content: [
          { type: "image", source: { type: "base64", media_type: mediaType, data: image } },
          { type: "text", text: prompt },
        ],
      }],
    }),
  });
  if (!r.ok) {
    const t = await r.text();
    console.error("Anthropic", r.status, t);
    const msg = r.status === 401 ? "API-Key ungültig." : r.status === 429 ? "Zu viele Anfragen, bitte kurz warten." :
      r.status === 400 && t.includes("credit") ? "Kein Guthaben im Anthropic-Konto." : "Erkennung fehlgeschlagen (" + r.status + ").";
    return json({ error: msg }, 502);
  }
  const out = await r.json();
  const text: string = (out.content ?? []).filter((c: { type: string }) => c.type === "text").map((c: { text: string }) => c.text).join("");
  const m = text.match(/\{[\s\S]*\}/);
  try {
    const parsed = JSON.parse(m ? m[0] : text);
    const pairs = (Array.isArray(parsed.pairs) ? parsed.pairs : [])
      .filter((p: { term?: unknown; definition?: unknown }) => p && p.term && p.definition)
      .map((p: { term: unknown; definition: unknown }) => ({ term: String(p.term), definition: String(p.definition) }));
    return json({ pairs });
  } catch {
    return json({ error: "Antwort konnte nicht gelesen werden. Bitte erneut versuchen." }, 502);
  }
});
