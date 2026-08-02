# LEBONPLAN

Plateforme de bons plans **100 % en ligne** (failles de prix, alternatives légales, voyage via sites reconnus, codes promo, offres officielles, cashback). Aucune vente entre particuliers.

Le front est une application statique autonome (`index.html`). Elle fonctionne **en mode démo** (données en mémoire) sans backend, et bascule sur **Supabase** dès que les clés sont renseignées — sans changer le code de l'UI.

---

## Structure du projet

```
lebonplan/
├─ index.html                 ← l'application (UI complète)
├─ js/
│  ├─ config.js               ← tes clés Supabase + flag USE_SUPABASE
│  ├─ supabase.js             ← création du client Supabase
│  ├─ api.js                  ← couche d'accès aux données (toutes les requêtes)
│  └─ bootstrap.js            ← hydrate les données + realtime au chargement
├─ supabase/
│  ├─ schema.sql              ← tables + sécurité (RLS) + règles serveur
│  ├─ seed.sql                ← données de démo (optionnel)
│  └─ functions/og-image/     ← Edge Function : récupère l'og:image d'un lien
├─ .env.example
└─ .gitignore
```

## Comment ça marche (démo ↔ Supabase)

- `js/config.js` → `USE_SUPABASE: false` : l'app tourne en **démo** (tout en mémoire, remis à zéro au rechargement).
- `USE_SUPABASE: true` + clés : au chargement, `bootstrap.js` ouvre une session, **remplace les données de démo** par celles de Supabase, et branche le **temps réel**. Les écritures (publier, favori, validation, alerte, ban, vues) partent vers Supabase via les appels `LBP.api.*` déjà présents dans `index.html` (gardés par `if (window.LBP && LBP.enabled)`).

---

## Mise en route Supabase (10 min)

1. **Créer le projet** sur https://supabase.com → note l'`URL` et la clé `anon public` (Project Settings → API).
2. **Base de données** : Supabase → SQL Editor → colle/exécute `supabase/schema.sql` (puis `supabase/seed.sql` si tu veux des plans de démo).
3. **Auth** : Authentication → Providers →
   - active **Email** (connexion / inscription email + mot de passe) ;
   - pour tester sans email de confirmation en dev : Authentication → Providers → Email → décoche **"Confirm email"** (les comptes sont utilisables immédiatement). En prod, laisse la confirmation activée.
   - active aussi **Anonymous sign-ins** (bouton « Continuer en invité »).
4. **Edge Function og:image** (récupère la vraie image des plans depuis leur lien) :
   ```bash
   npm i -g supabase
   supabase login
   supabase link --project-ref <ref-du-projet>
   supabase functions deploy og-image
   ```
5. **Clés** : ouvre `js/config.js` et renseigne :
   ```js
   USE_SUPABASE: true,
   SUPABASE_URL: 'https://xxxx.supabase.co',
   SUPABASE_ANON_KEY: 'eyJhbGciOi...',
   ```
6. **Lancer en local** (serveur statique — nécessaire pour charger les fichiers `js/`) :
   ```bash
   npx serve .        # ou : python3 -m http.server 8080
   ```
   Ouvre l'URL indiquée. En console tu dois voir `Supabase activé` puis `Données hydratées depuis Supabase`.

---

## Déploiement (hébergement statique)

N'importe quel hébergeur de site statique convient (Netlify, Vercel, Cloudflare Pages, GitHub Pages).
- Racine de publication : le dossier `lebonplan/`.
- Renseigne les clés dans `js/config.js` (ou injecte-les au build).

## Pousser sur Git

```bash
cd lebonplan
git init
git add .
git commit -m "LEBONPLAN — front + structure Supabase"
git branch -M main
git remote add origin <ton-repo-git>
git push -u origin main
```

> ⚠️ Ne committe pas de fichier `.env` avec des secrets (`.gitignore` le prévoit). La clé `anon` est publique (prévue pour le front) ; la clé `service_role` ne doit **jamais** aller dans le front.

---

## Modèle de données (résumé)

| Table            | Rôle |
|------------------|------|
| `profiles`       | 1 par utilisateur (username, niveau, `fake_plans_count`, `banned`) |
| `access_codes`   | codes d'accès du gate d'entrée |
| `deals`          | les plans (prix/code, catégorie, lien, image, vidéo, étapes, `views`, `validations`, `status`) |
| `favorites`      | favoris par utilisateur |
| `validations`    | « utilisé et validé » (unique par user/plan) → incrémente `deals.validations` |
| `alerts`         | alertes (mot-clé + catégorie) |
| `notifications`  | notifications (déclenchées par le moteur d'alertes) |
| `reports`        | signalements / bans |

**Règles serveur incluses**
- `fn_evaluate_alerts` (trigger) : à chaque nouveau plan, notifie les alertes correspondantes.
- `fn_validation_count` (trigger) : maintient `deals.validations`.
- `fn_ban_deal(deal, reason)` (RPC) : retire le plan, avertit l'auteur, +1 faux plan, **ban auto au 3e**.
- `fn_increment_views(deal)` (RPC) : compteur de vues.
- Vue `deals_ranked` : score « Plan du moment » = `views + validations × 25`.
- **RLS** activée sur toutes les tables (chacun gère ses données ; plans « live » lisibles par tous).

## Parcours utilisateur (mode Supabase)
1. **Code d'accès** → vérifié via la table `access_codes` (`LBP.api.verifyAccessCode`). En démo, tout code à 4 chiffres passe.
2. **Connexion / Inscription** (écran `s-auth`) : email + mot de passe, ou **« Continuer en invité »** (session anonyme). Un utilisateur déjà connecté saute cette étape.
3. **Application** : les données sont hydratées depuis Supabase ; publier / favori / validation / alerte / ban / vues sont persistés. Bouton **« Se déconnecter »** dans la barre latérale.

## À finaliser côté toi (optionnel)
- Ajouter des providers OAuth (Google, Apple…) : Authentication → Providers, puis un bouton appelant `supabase.auth.signInWithOAuth`.
- Régie publicitaire réelle (les emplacements « pub d'ouverture » et « pub 2 min » sont déjà en place côté UI).
- Récupérer l'og:image à la publication : appeler `LBP.api.fetchOgImage(lien)` dans `submitPublish` avant l'insert (l'Edge Function est prête).
- Enrichir la page profil (stats réelles, plans postés de l'utilisateur) — le nom/identité est déjà branché.
