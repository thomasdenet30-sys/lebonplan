-- ============================================================
-- LEBONPLAN — Données de démonstration (optionnel)
-- À exécuter APRÈS schema.sql.
--
-- Pas de profil "démo" inventé : public.profiles.id référence auth.users(id),
-- donc insérer un id fictif viole la clé étrangère et annule tout le script.
-- Les plans de démo sont donc sans auteur ; le front affiche « Membre »
-- (js/api.js, dbToDeal). Voir en bas pour les rattacher à un vrai compte.
--
-- Ré-exécutable : chaque plan n'est inséré que si son titre est absent.
-- ============================================================

with demo(cat, icon, title, price_now, price_old, discount, expires,
          description, tags, views, validations, verified, video) as (
  values
   ('Failles','bolt','Erreur de prix : vol long-courrier à -80 %','149 €','740 €','-80%','Corrigé bientôt','Erreur tarifaire repérée sur un comparateur reconnu. À réserver vite.', array['Erreur de prix','Comparateur reconnu','Flash'],22000,820,true,'https://www.youtube.com/watch?v=aqz-KE-bpKQ'),
   ('Codes promo','mode','Code -30 % dès le premier achat','MEMBRE30',null,'Code','48 h','Code de bienvenue cumulable avec la livraison offerte.', array['Code promo','Cumulable','Première commande'],9200,240,true,null),
   ('Voyage','voyage','Nuit hôtel 4★ -40 % — plateforme officielle','99 €','165 €','-40%','Ce week-end','Offre flash sur une plateforme de réservation reconnue.', array['Site reconnu','Annulation gratuite','4 étoiles'],7400,190,true,null),
   ('Officiel','shield','Aide officielle : abonnement transport -50 % (-26 ans)','-50 %',null,'-50%','Ce mois-ci','Dispositif officiel pour les moins de 26 ans.', array['Organisme officiel','-26 ans','Officiel'],12800,410,true,null),
   ('Alternatives','layers','Alternative streaming : même concept, 65 % moins cher','3,99 €','11,99 €','-65%','En ce moment','Plateforme indépendante et légale, sans engagement.', array['Alternative légale','Même concept','Sans engagement'],11200,340,true,null),
   ('Cashback','trend','Cashback 15 % via plateforme reconnue','15 %',null,'15 %','Permanent','Cumule ta remise habituelle avec 15 % de cashback.', array['Cashback','Cumulable','Plateforme reconnue'],3300,95,false,null)
)
insert into public.deals (author, cat, icon, title, price_now, price_old, discount,
                          expires, description, tags, views, validations, verified, video)
select null::uuid, d.cat, d.icon, d.title, d.price_now, d.price_old, d.discount,
       d.expires, d.description, d.tags, d.views, d.validations, d.verified, d.video
from demo d
where not exists (select 1 from public.deals x where x.title = d.title);

-- ------------------------------------------------------------
-- Optionnel : rattacher les plans de démo à ton compte, une fois inscrit
-- via le site (l'inscription crée le profil automatiquement).
-- Décommente et remplace l'adresse :
--
-- update public.deals
--    set author = (select id from auth.users where email = 'toi@exemple.fr')
--  where author is null;
-- ------------------------------------------------------------
