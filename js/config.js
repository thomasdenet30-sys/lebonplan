/* ============================================================
   LEBONPLAN — Configuration
   Renseigne tes clés Supabase puis passe USE_SUPABASE à true.
   (Ces valeurs peuvent aussi être injectées au build / via variables
    d'environnement de ton hébergeur — voir README.)
   ============================================================ */
window.LBP_CONFIG = {
  // ← passe à true une fois supabase/schema.sql appliqué au projet
  USE_SUPABASE: false,
  SUPABASE_URL: 'https://trwobwbrrmjgaqzurbaa.supabase.co',
  // Clé publishable : conçue pour le navigateur, elle ne donne accès qu'à ce
  // que les RLS autorisent. Jamais de service_role / secret key ici.
  SUPABASE_ANON_KEY: 'sb_publishable_vaxudx8Owu0FQCrrYgvi4g_BopQyRZa',
  ACCESS_CODE_FALLBACK: '2024',      // code d'accès de démo si Supabase est off
};
