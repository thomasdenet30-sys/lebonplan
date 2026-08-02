/* ============================================================
   LEBONPLAN — Couche d'accès aux données (API Supabase)
   Toutes les lectures/écritures passent par ici. Le reste du code
   (index.html) appelle window.LBP.api.* uniquement quand LBP.enabled.
   ============================================================ */
(function () {
  window.LBP = window.LBP || {};
  var L = window.LBP;
  function sb() { return L.sb; }
  function user() { return L._user; }

  /* ---- Mapping BDD <-> objet "deal" utilisé par l'UI ---- */
  function dbToDeal(r) {
    var uname = (r.profiles && r.profiles.username) || 'Membre';
    return {
      id: r.id,
      user: uname,
      av: uname.slice(0, 2).toUpperCase(),
      cat: r.cat, icon: r.icon, disc: r.discount, exp: r.expires || '',
      title: r.title, now: r.price_now || '', old: r.price_old || '',
      desc: r.description || '', tags: r.tags || [], votes: 0,
      views: r.views || 0, validated: r.validations || 0, verified: !!r.verified,
      link: r.link || '', domain: r.domain || '', image: r.image || '',
      video: r.video || '', steps: r.steps || []
    };
  }
  function dealToDb(d) {
    return {
      cat: d.cat, icon: d.icon, title: d.title, price_now: d.now, price_old: d.old,
      discount: d.disc, expires: d.exp, description: d.desc, tags: d.tags,
      link: d.link || null, domain: d.domain || null, image: d.image || null,
      video: d.video || null, steps: d.steps || []
      // verified/views/validations volontairement absents : colonnes non
      // écrivables par le client (grant ciblé côté schéma), sinon l'insertion
      // serait rejetée en « permission denied for column ».
    };
  }

  L.api = {
    /* ----- Session (identité pour favoris / alertes / validations) -----
       Anonyme par défaut. Remplace par un vrai login (email, OAuth…) si besoin. */
    async ensureSession() {
      var res = await sb().auth.getUser();
      if (res.data && res.data.user) { L._user = res.data.user; return L._user; }
      var out = await sb().auth.signInAnonymously();
      if (out.error) console.warn('[LEBONPLAN] auth', out.error);
      L._user = out.data && out.data.user;
      return L._user;
    },

    /* ----- Authentification (email / mot de passe + invité) ----- */
    async currentUser() {
      var res = await sb().auth.getUser();
      L._user = (res.data && res.data.user) || null;
      return L._user;
    },
    async signUp(email, password, username) {
      var out = await sb().auth.signUp({ email: email, password: password, options: { data: { username: username } } });
      if (out.error) throw out.error;
      L._user = out.data.user;
      return out.data;                 // data.session peut être null si confirmation email requise
    },
    async signIn(email, password) {
      var out = await sb().auth.signInWithPassword({ email: email, password: password });
      if (out.error) throw out.error;
      L._user = out.data.user; return out.data.user;
    },
    async signInAnonymous() {
      var out = await sb().auth.signInAnonymously();
      if (out.error) throw out.error;
      L._user = out.data.user; return out.data.user;
    },
    async signOut() { await sb().auth.signOut(); L._user = null; },

    /* ----- Code d'accès (table access_codes) ----- */
    async verifyAccessCode(code) {
      var out = await sb().from('access_codes').select('code').eq('code', code).eq('active', true).maybeSingle();
      return !!(out.data);
    },

    /* ----- Lectures ----- */
    async getDeals() {
      var out = await sb().from('deals').select('*, profiles:author(username)').eq('status', 'live').order('created_at', { ascending: false });
      if (out.error) { console.warn(out.error); return []; }
      return out.data.map(dbToDeal);
    },
    async getFavorites() {
      var u = user(); if (!u) return [];
      var out = await sb().from('favorites').select('deal_id').eq('user_id', u.id);
      return (out.data || []).map(function (r) { return r.deal_id; });
    },
    async getAlerts() {
      var u = user(); if (!u) return [];
      var out = await sb().from('alerts').select('*').eq('user_id', u.id).order('created_at', { ascending: false });
      return (out.data || []).map(function (r) { return { id: r.id, keyword: r.keyword || '', cat: r.cat || '', active: r.active }; });
    },
    async getNotifications() {
      var u = user(); if (!u) return [];
      var out = await sb().from('notifications').select('*').eq('user_id', u.id).order('created_at', { ascending: false }).limit(50);
      return (out.data || []).map(function (r) { return { id: r.id, title: r.title, text: r.body, icon: r.icon, read: r.read, dealId: r.deal_id }; });
    },
    async getMyValidations() {
      var u = user(); if (!u) return [];
      var out = await sb().from('validations').select('deal_id').eq('user_id', u.id);
      return (out.data || []).map(function (r) { return r.deal_id; });
    },

    /* ----- Écritures ----- */
    async insertDeal(d) {
      var u = user();
      var row = Object.assign(dealToDb(d), { author: u ? u.id : null });
      var out = await sb().from('deals').insert(row).select('id').single();
      if (out.error) { console.warn(out.error); return null; }
      d.id = out.data.id;               // aligne l'id local sur l'id BDD
      return out.data.id;               // le trigger d'alertes s'exécute côté serveur
    },
    async setFavorite(dealId, on) {
      var u = user(); if (!u) return;
      if (on) await sb().from('favorites').upsert({ user_id: u.id, deal_id: dealId });
      else await sb().from('favorites').delete().eq('user_id', u.id).eq('deal_id', dealId);
    },
    async addValidation(dealId) {
      var u = user(); if (!u) return;
      await sb().from('validations').upsert({ user_id: u.id, deal_id: dealId }); // trigger → deals.validations++
    },
    async insertAlert(a) {
      var u = user(); if (!u) return;
      var out = await sb().from('alerts').insert({ user_id: u.id, keyword: a.keyword || null, cat: a.cat || null, active: true }).select('id').single();
      if (out.data) a.id = out.data.id;
    },
    async setAlertActive(id, active) { await sb().from('alerts').update({ active: active }).eq('id', id); },
    async deleteAlert(id) { await sb().from('alerts').delete().eq('id', id); },
    async markNotificationsRead() {
      var u = user(); if (!u) return;
      await sb().from('notifications').update({ read: true }).eq('user_id', u.id).eq('read', false);
    },

    /* ----- Modération : ban (RPC serveur) ----- */
    async banDeal(dealId, reason) {
      var out = await sb().rpc('fn_ban_deal', { p_deal: dealId, p_reason: reason });
      if (out.error) console.warn(out.error);
    },

    /* ----- Vues ----- */
    async incrementViews(dealId) { await sb().rpc('fn_increment_views', { p_deal: dealId }); },

    /* ----- og:image via Edge Function (à partir du lien du plan) ----- */
    async fetchOgImage(url) {
      var out = await sb().functions.invoke('og-image', { body: { url: url } });
      if (out.error) { console.warn(out.error); return ''; }
      return (out.data && out.data.image) || '';
    }
  };
})();
