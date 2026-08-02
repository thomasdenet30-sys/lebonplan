-- ============================================================
-- LEBONPLAN — Données de démonstration (optionnel)
-- À exécuter APRÈS schema.sql. Les plans sont attribués à un
-- profil "démo". Adapte / supprime selon tes besoins.
-- ============================================================

-- Profil démo (id fixe pour les seeds ; en prod, les auteurs sont de vrais users)
insert into public.profiles (id, username, level)
values ('00000000-0000-0000-0000-000000000001', 'LEBONPLAN', 9)
on conflict (id) do nothing;

insert into public.deals (author, cat, icon, title, price_now, price_old, discount, expires, description, tags, views, validations, verified, video)
values
 ('00000000-0000-0000-0000-000000000001','Failles','bolt','Erreur de prix : vol long-courrier à -80 %','149 €','740 €','-80%','Corrigé bientôt','Erreur tarifaire repérée sur un comparateur reconnu. À réserver vite.', array['Erreur de prix','Comparateur reconnu','Flash'],22000,820,true,'https://www.youtube.com/watch?v=aqz-KE-bpKQ'),
 ('00000000-0000-0000-0000-000000000001','Codes promo','mode','Code -30 % dès le premier achat','MEMBRE30',null,'Code','48 h','Code de bienvenue cumulable avec la livraison offerte.', array['Code promo','Cumulable','Première commande'],9200,240,true,null),
 ('00000000-0000-0000-0000-000000000001','Voyage','voyage','Nuit hôtel 4★ -40 % — plateforme officielle','99 €','165 €','-40%','Ce week-end','Offre flash sur une plateforme de réservation reconnue.', array['Site reconnu','Annulation gratuite','4 étoiles'],7400,190,true,null),
 ('00000000-0000-0000-0000-000000000001','Officiel','shield','Aide officielle : abonnement transport -50 % (-26 ans)','-50 %',null,'-50%','Ce mois-ci','Dispositif officiel pour les moins de 26 ans.', array['Organisme officiel','-26 ans','Officiel'],12800,410,true,null),
 ('00000000-0000-0000-0000-000000000001','Alternatives','layers','Alternative streaming : même concept, 65 % moins cher','3,99 €','11,99 €','-65%','En ce moment','Plateforme indépendante et légale, sans engagement.', array['Alternative légale','Même concept','Sans engagement'],11200,340,true,null),
 ('00000000-0000-0000-0000-000000000001','Cashback','trend','Cashback 15 % via plateforme reconnue','15 %',null,'15 %','Permanent','Cumule ta remise habituelle avec 15 % de cashback.', array['Cashback','Cumulable','Plateforme reconnue'],3300,95,false,null)
on conflict do nothing;
