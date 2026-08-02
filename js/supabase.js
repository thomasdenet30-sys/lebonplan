/* ============================================================
   LEBONPLAN — Initialisation du client Supabase
   Charge supabase-js (via CDN, voir index.html) et crée le client
   uniquement si la config est complète. Sinon → mode démo.
   ============================================================ */
(function () {
  window.LBP = window.LBP || {};
  var c = window.LBP_CONFIG || {};
  var ready = c.USE_SUPABASE && c.SUPABASE_URL && c.SUPABASE_ANON_KEY && window.supabase;
  if (ready) {
    window.LBP.sb = window.supabase.createClient(c.SUPABASE_URL, c.SUPABASE_ANON_KEY, {
      auth: { persistSession: true, autoRefreshToken: true }
    });
    window.LBP.enabled = true;
    console.log('[LEBONPLAN] Supabase activé');
  } else {
    window.LBP.enabled = false;
    if (c.USE_SUPABASE) console.warn('[LEBONPLAN] USE_SUPABASE=true mais clés manquantes ou supabase-js non chargé → mode démo');
  }
})();
