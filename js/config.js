/* ============================================================
   LEBONPLAN — Configuration
   Renseigne tes clés Supabase puis passe USE_SUPABASE à true.
   (Ces valeurs peuvent aussi être injectées au build / via variables
    d'environnement de ton hébergeur — voir README.)
   ============================================================ */
window.LBP_CONFIG = {
  USE_SUPABASE: false,               // ← passe à true une fois les clés renseignées
  SUPABASE_URL: '',                  // ex : https://xxxxxxxx.supabase.co
  SUPABASE_ANON_KEY: '',             // clé "anon public" (Project Settings → API)
  ACCESS_CODE_FALLBACK: '2024',      // code d'accès de démo si Supabase est off
};
