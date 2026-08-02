/* ============================================================
   LEBONPLAN — Initialisation du client Supabase
   Charge supabase-js (via CDN, voir index.html) et crée le client
   uniquement si la config est complète. Sinon → mode démo.
   ============================================================ */
(function () {
  window.LBP = window.LBP || {};
  var c = window.LBP_CONFIG || {};
  var voulu = !!(c.USE_SUPABASE && c.SUPABASE_URL && c.SUPABASE_ANON_KEY);
  var ready = voulu && window.supabase;
  if (ready) {
    window.LBP.sb = window.supabase.createClient(c.SUPABASE_URL, c.SUPABASE_ANON_KEY, {
      auth: { persistSession: true, autoRefreshToken: true }
    });
    window.LBP.enabled = true;
    console.log('[LEBONPLAN] Supabase activé');
  } else {
    window.LBP.enabled = false;
    // Distingue une démo assumée (USE_SUPABASE=false) d'un échec d'initialisation.
    // Sans ce drapeau, une panne du CDN faisait basculer le site en mode démo
    // sans rien dire : portail ouvert à n'importe quel code et données factices.
    window.LBP.initFailed = voulu;
    if (voulu) console.error('[LEBONPLAN] supabase-js indisponible (CDN ?) — le site refuse de basculer en démo');
  }
})();
