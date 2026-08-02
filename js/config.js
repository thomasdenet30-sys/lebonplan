/* ============================================================
   LEBONPLAN — Configuration
   Renseigne tes clés Supabase puis passe USE_SUPABASE à true.
   (Ces valeurs peuvent aussi être injectées au build / via variables
    d'environnement de ton hébergeur — voir README.)
   ============================================================ */
window.LBP_CONFIG = {
  // schema.sql appliqué le 2026-08-02 : les 9 tables/vues répondent et les RLS
  // ont été vérifiées en anonyme (lecture OK, écritures refusées).
  USE_SUPABASE: true,
  SUPABASE_URL: 'https://trwobwbrrmjgaqzurbaa.supabase.co',
  // Clé publishable : conçue pour le navigateur, elle ne donne accès qu'à ce
  // que les RLS autorisent. Jamais de service_role / secret key ici.
  SUPABASE_ANON_KEY: 'sb_publishable_vaxudx8Owu0FQCrrYgvi4g_BopQyRZa',
  ACCESS_CODE_FALLBACK: '2024',      // code d'accès de démo si Supabase est off
};
