/* ============================================================
   LEBONPLAN — Bootstrap Supabase
   - Au chargement : reprend une session existante (utilisateur déjà
     connecté) et hydrate. Sinon, l'écran de connexion (s-auth) gère
     l'authentification, puis appelle LBP.hydrate().
   - Expose : LBP.hydrate(), LBP.applyIdentity().
   Si Supabase est off → rien ne se passe (mode démo).
   ============================================================ */
(function () {
  window.LBP = window.LBP || {};
  var L = window.LBP;
  if (!L.enabled) return;

  var subbed = false;
  function subscribeRealtime() {
    if (subbed) return; subbed = true;
    L.sb.channel('deals-live')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'deals' }, function () {
        L.api.getDeals().then(function (d) {
          if (!d.length || typeof DEALS === 'undefined') return;
          DEALS.length = 0; d.forEach(function (x) { DEALS.push(x); });
          if (typeof computeMoment === 'function') momentId = computeMoment();
          if (typeof renderFeed === 'function') renderFeed();
        });
      })
      .subscribe();
  }

  // Met à jour l'identité affichée (nom, initiales, profil)
  L.applyIdentity = async function () {
    var u = L._user; if (!u) return;
    var name = (u.user_metadata && u.user_metadata.username) || (u.email ? u.email.split('@')[0] : 'Membre');
    try {
      var out = await L.sb.from('profiles').select('username').eq('id', u.id).maybeSingle();
      if (out.data && out.data.username) name = out.data.username;
    } catch (e) { /* ignore */ }
    var ini = name.slice(0, 2).toUpperCase();
    document.querySelectorAll('.prof-av, .side .me .av').forEach(function (el) { el.textContent = ini; });
    document.querySelectorAll('.avatar').forEach(function (el) {
      if (el.firstChild && el.firstChild.nodeType === 3) el.firstChild.nodeValue = ini;
    });
    var pn = document.querySelector('.prof-name'); if (pn) pn.textContent = name;
    var ph = document.querySelector('.prof-handle'); if (ph) ph.textContent = '@' + name.toLowerCase().replace(/\s+/g, '') + ' · membre';
    var me = document.querySelector('.side .me .info b'); if (me) me.textContent = name;
  };

  // Charge toutes les données de l'utilisateur et rafraîchit l'UI
  L.hydrate = async function () {
    try {
      var r = await Promise.all([
        L.api.getDeals(), L.api.getFavorites(), L.api.getAlerts(),
        L.api.getNotifications(), L.api.getMyValidations()
      ]);
      var deals = r[0], favs = r[1], als = r[2], notifs = r[3], vals = r[4];
      // Remplacement inconditionnel : garder l'ancien contenu quand la base ne
      // renvoie rien afficherait des plans qui n'existent plus côté serveur.
      if (typeof DEALS !== 'undefined') { DEALS.length = 0; deals.forEach(function (d) { DEALS.push(d); }); }
      if (typeof favorites !== 'undefined') { favorites.clear(); favs.forEach(function (id) { favorites.add(id); }); }
      if (typeof validatedByUser !== 'undefined') { validatedByUser.clear(); vals.forEach(function (id) { validatedByUser.add(id); }); }
      if (typeof alerts !== 'undefined') { alerts.length = 0; als.forEach(function (a) { alerts.push(a); }); }
      if (typeof notifications !== 'undefined') { notifications.length = 0; notifs.forEach(function (n) { notifications.push(n); }); }
      if (typeof computeMoment === 'function' && typeof momentId !== 'undefined') momentId = computeMoment();
      await L.applyIdentity();
      if (typeof renderFeed === 'function') renderFeed();
      if (typeof updateCounts === 'function') updateCounts();
      subscribeRealtime();
      console.log('[LEBONPLAN] Données hydratées depuis Supabase');
    } catch (e) {
      console.error('[LEBONPLAN] Hydratation échouée', e);
    }
  };

  document.addEventListener('DOMContentLoaded', async function () {
    try {
      await L.api.currentUser();            // reprend une session existante si présente
      if (L._user) { await L.hydrate(); }   // utilisateur déjà connecté → on précharge
    } catch (e) { console.warn('[LEBONPLAN] session', e); }
  });
})();
