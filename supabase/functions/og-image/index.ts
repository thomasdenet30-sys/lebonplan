// ============================================================
// LEBONPLAN — Edge Function "og-image"
// Récupère l'image officielle (og:image) d'une page à partir de
// son URL. Contourne le CORS (impossible côté navigateur).
// Déploiement :  supabase functions deploy og-image
// Appel (client) : LBP.api.fetchOgImage(url)
// ============================================================
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function abs(url: string, base: string): string {
  try { return new URL(url, base).toString(); } catch { return url; }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const { url } = await req.json();
    if (!url) return json({ error: "url manquante" }, 400);

    const target = /^https?:\/\//i.test(url) ? url : "https://" + url;
    const res = await fetch(target, {
      headers: { "User-Agent": "Mozilla/5.0 (compatible; LebonplanBot/1.0)" },
      redirect: "follow",
    });
    const html = await res.text();

    const pick = (re: RegExp) => { const m = html.match(re); return m ? m[1] : ""; };
    let image =
      pick(/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i) ||
      pick(/<meta[^>]+name=["']twitter:image["'][^>]+content=["']([^"']+)["']/i) ||
      pick(/<link[^>]+rel=["']image_src["'][^>]+href=["']([^"']+)["']/i);

    if (image) image = abs(image, target);
    // Repli : favicon haute résolution
    const host = new URL(target).hostname;
    const favicon = `https://www.google.com/s2/favicons?domain=${host}&sz=128`;

    return json({ image: image || favicon, favicon, domain: host.replace(/^www\./, "") });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
