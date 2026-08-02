-- ============================================================
-- LEBONPLAN — Schéma Supabase (PostgreSQL)
-- À exécuter dans Supabase → SQL Editor (ou via `supabase db push`).
-- Contient : tables, index, sécurité RLS, et les règles serveur
-- (validations, moteur d'alertes, bannissement au 3e faux plan).
-- ============================================================

create extension if not exists "pgcrypto";

-- ------------------------------------------------------------
-- PROFILS (1 ligne par utilisateur auth)
-- ------------------------------------------------------------
create table if not exists public.profiles (
  id                uuid primary key references auth.users(id) on delete cascade,
  username          text unique,
  avatar            text,
  level             int  not null default 1,
  fake_plans_count  int  not null default 0,   -- compteur "faux plans"
  banned            boolean not null default false,
  created_at        timestamptz not null default now()
);

-- Crée automatiquement un profil à l'inscription
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username)
  values (new.id, coalesce(new.raw_user_meta_data->>'username', 'membre_' || substr(new.id::text, 1, 6)))
  on conflict (id) do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ------------------------------------------------------------
-- CODES D'ACCÈS (gate d'entrée du site)
-- ------------------------------------------------------------
create table if not exists public.access_codes (
  code       text primary key,
  active     boolean not null default true,
  label      text,
  created_at timestamptz not null default now()
);
insert into public.access_codes (code, label) values ('1984', 'Code de lancement')
  on conflict (code) do nothing;

-- ------------------------------------------------------------
-- PLANS
-- ------------------------------------------------------------
create table if not exists public.deals (
  id           bigint generated always as identity primary key,
  author       uuid references public.profiles(id) on delete set null,
  cat          text not null,                    -- Failles, Alternatives, Voyage, Codes promo, Officiel, Tech, Cashback
  icon         text,                             -- visuel auto (bolt, layers, voyage, mode, shield, tech, trend, boat…)
  title        text not null,
  price_now    text,                             -- prix OU code (ex. "29 €" ou "MEMBRE30")
  price_old    text,
  discount     text,                             -- "-80%", "Code", "Cashback"…
  expires      text,                             -- libellé ("48 h", "Ce week-end") — passe en timestamptz si tu veux du vrai
  description  text,
  tags         text[] default '{}',
  link         text,                             -- lien du site reconnu / officiel
  domain       text,
  image        text,                             -- og:image (rempli par l'Edge Function) ou favicon
  video        text,                             -- lien vidéo explicative (YouTube/Vimeo…)
  steps        text[] default '{}',              -- "comment en profiter"
  views        int not null default 0,
  validations  int not null default 0,           -- maintenu par trigger
  verified     boolean not null default false,
  status       text not null default 'live',     -- live | banned
  created_at   timestamptz not null default now()
);
create index if not exists deals_cat_idx     on public.deals (cat);
create index if not exists deals_status_idx  on public.deals (status);
create index if not exists deals_created_idx on public.deals (created_at desc);

-- Score & classement "Plan du moment"
-- security_invoker : sans cette option une vue s'exécute avec les droits de son
-- créateur et court-circuite donc les RLS de public.deals.
create or replace view public.deals_ranked
  with (security_invoker = true) as
  select *, (views + validations * 25) as score
  from public.deals
  where status = 'live'
  order by score desc;

-- ------------------------------------------------------------
-- FAVORIS
-- ------------------------------------------------------------
create table if not exists public.favorites (
  user_id    uuid   not null references public.profiles(id) on delete cascade,
  deal_id    bigint not null references public.deals(id)    on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, deal_id)
);

-- ------------------------------------------------------------
-- VALIDATIONS ("utilisé et validé", unique par user/plan)
-- ------------------------------------------------------------
create table if not exists public.validations (
  user_id    uuid   not null references public.profiles(id) on delete cascade,
  deal_id    bigint not null references public.deals(id)    on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, deal_id)
);

-- Maintient deals.validations à jour
create or replace function public.fn_validation_count()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (tg_op = 'INSERT') then
    update public.deals set validations = validations + 1 where id = new.deal_id;
  elsif (tg_op = 'DELETE') then
    update public.deals set validations = greatest(validations - 1, 0) where id = old.deal_id;
  end if;
  return null;
end; $$;

drop trigger if exists trg_validation_count on public.validations;
create trigger trg_validation_count
  after insert or delete on public.validations
  for each row execute function public.fn_validation_count();

-- ------------------------------------------------------------
-- ALERTES
-- ------------------------------------------------------------
create table if not exists public.alerts (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  keyword    text,
  cat        text,
  active     boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists alerts_user_idx on public.alerts (user_id);

-- ------------------------------------------------------------
-- NOTIFICATIONS
-- ------------------------------------------------------------
create table if not exists public.notifications (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  deal_id    bigint references public.deals(id) on delete set null,
  title      text,
  body       text,
  icon       text,
  read       boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists notif_user_idx on public.notifications (user_id, read);

-- ------------------------------------------------------------
-- SIGNALEMENTS / BAN
-- ------------------------------------------------------------
create table if not exists public.reports (
  id         bigint generated always as identity primary key,
  deal_id    bigint not null references public.deals(id) on delete cascade,
  reporter   uuid references public.profiles(id) on delete set null,
  reason     text,                                -- mensonge | obsolète | arnaque
  created_at timestamptz not null default now()
);
-- Un seul signalement par membre et par plan : c'est ce qui donne son sens au
-- seuil de 3 (sinon un seul compte atteindrait le seuil en trois clics).
create unique index if not exists reports_deal_reporter_idx
  on public.reports (deal_id, reporter);

-- ============================================================
-- MOTEUR D'ALERTES : à l'insertion d'un plan, notifie les alertes
-- correspondantes (mot-clé et/ou catégorie).
-- ============================================================
create or replace function public.fn_evaluate_alerts()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  a record;
  haystack text;
begin
  haystack := lower(coalesce(new.title,'') || ' ' || coalesce(new.cat,'') || ' ' || array_to_string(coalesce(new.tags,'{}'), ' '));
  for a in
    select * from public.alerts
    where active = true
      and (cat is null or cat = new.cat)
      and (keyword is null or keyword = '' or haystack like '%' || lower(keyword) || '%')
  loop
    insert into public.notifications (user_id, deal_id, title, body, icon)
    values (
      a.user_id, new.id, 'Nouveau plan pour toi',
      '« ' || new.title || ' » correspond à ton alerte '
        || coalesce('« ' || a.keyword || ' »', a.cat, 'tous les plans') || '.',
      new.icon
    );
  end loop;
  return new;
end; $$;

drop trigger if exists trg_evaluate_alerts on public.deals;
create trigger trg_evaluate_alerts
  after insert on public.deals
  for each row execute function public.fn_evaluate_alerts();

-- ============================================================
-- BAN : retire le plan, avertit l'auteur, +1 "faux plan",
-- bannit le profil au 3e faux plan.
-- Fonction INTERNE : déclenchée par fn_report_deal une fois le seuil de
-- signalements atteint, jamais appelable depuis le client (revoke plus bas).
-- ============================================================
create or replace function public.fn_ban_deal(p_deal bigint, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_author uuid;
  v_title  text;
  v_count  int;
begin
  select author, title into v_author, v_title from public.deals where id = p_deal;
  if not found then return; end if;

  update public.deals set status = 'banned' where id = p_deal;

  if v_author is not null then
    update public.profiles
      set fake_plans_count = fake_plans_count + 1
      where id = v_author
      returning fake_plans_count into v_count;

    insert into public.notifications (user_id, deal_id, title, body, icon)
    values (v_author, p_deal, 'Un de tes plans a été retiré',
            '« ' || coalesce(v_title,'') || ' » a été signalé (' || coalesce(p_reason,'') ||
            '). Faux plans : ' || v_count || '/3.', 'alert');

    if v_count >= 3 then
      update public.profiles set banned = true where id = v_author;
      insert into public.notifications (user_id, title, body, icon)
      values (v_author, 'Profil banni', 'Ton profil a été banni automatiquement (3 faux plans confirmés).', 'ban');
    end if;
  end if;
end; $$;

-- Plus personne ne bannit directement : Postgres accorde l'EXECUTE à PUBLIC par
-- défaut, et un SECURITY DEFINER ignore les RLS.
revoke execute on function public.fn_ban_deal(bigint, text) from public, anon, authenticated;

-- ============================================================
-- Compte "vérifié" = e-mail confirmé. Source unique de vérité pour les actions
-- réservées aux vrais comptes (publication, signalement).
-- Lu dans auth.users et non dans auth.jwt() : user_metadata est modifiable par
-- l'utilisateur et les claims du JWT ne sont pas rafraîchis à la volée. Un
-- compte anonyme n'ayant pas d'e-mail, il est écarté par le même test.
-- SECURITY DEFINER pour lire auth.users ; ne révèle que le statut de l'appelant.
-- ============================================================
create or replace function public.is_verified_user()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from auth.users
     where id = auth.uid()
       and email_confirmed_at is not null
  );
$$;

revoke execute on function public.is_verified_user() from public, anon;
grant  execute on function public.is_verified_user() to authenticated;

-- ============================================================
-- SIGNALEMENT : enregistre un signalement (un seul par membre et par plan)
-- et ne bannit qu'au 3e signalement de membres distincts.
-- SECURITY DEFINER assumé : le reporter est imposé à auth.uid() et n'est pas
-- un paramètre, il ne peut donc pas être forgé pour fabriquer trois voix.
-- Réservé aux comptes à e-mail vérifié : sans ça, trois signInAnonymously()
-- suffisaient à réunir trois "membres distincts".
-- ============================================================
create or replace function public.fn_report_deal(p_deal bigint, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid    uuid := auth.uid();
  v_count  int;
  v_status text;
begin
  if v_uid is null then
    raise exception 'Authentification requise pour signaler un plan.'
      using errcode = '42501';
  end if;

  if not public.is_verified_user() then
    raise exception 'Signalement réservé aux comptes dont l''adresse e-mail est vérifiée.'
      using errcode = '42501';
  end if;

  select status into v_status from public.deals where id = p_deal;
  if not found then
    raise exception 'Plan introuvable.';
  end if;

  insert into public.reports (deal_id, reporter, reason)
  values (p_deal, v_uid, p_reason)
  on conflict (deal_id, reporter) do nothing;

  select count(distinct reporter) into v_count
    from public.reports
    where deal_id = p_deal and reporter is not null;

  if v_count >= 3 and v_status <> 'banned' then
    perform public.fn_ban_deal(p_deal, p_reason);
    v_status := 'banned';
  end if;

  return jsonb_build_object('reports', v_count, 'threshold', 3, 'banned', v_status = 'banned');
end; $$;

revoke execute on function public.fn_report_deal(bigint, text) from public, anon;
grant  execute on function public.fn_report_deal(bigint, text) to authenticated;

-- Incrément des vues
create or replace function public.fn_increment_views(p_deal bigint)
returns void language sql security definer set search_path = public as $$
  update public.deals set views = views + 1 where id = p_deal;
$$;

-- ============================================================
-- SÉCURITÉ (Row Level Security)
-- ============================================================
alter table public.profiles     enable row level security;
alter table public.deals        enable row level security;
alter table public.favorites    enable row level security;
alter table public.validations  enable row level security;
alter table public.alerts       enable row level security;
alter table public.notifications enable row level security;
alter table public.reports      enable row level security;
alter table public.access_codes enable row level security;

-- Chaque policy est droppée avant d'être recréée : `create policy` échoue si
-- elle existe déjà, sinon le script n'est pas ré-exécutable.

-- Profils : lecture publique, mise à jour de soi
drop policy if exists profiles_read   on public.profiles;
drop policy if exists profiles_update on public.profiles;
create policy profiles_read   on public.profiles for select using (true);
create policy profiles_update on public.profiles for update
  to authenticated
  using      ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

-- Une policy RLS filtre des lignes, pas des colonnes : sans ce grant ciblé un
-- membre banni pourrait écrire banned = false ou remettre fake_plans_count à 0.
revoke update on public.profiles from anon, authenticated;
grant  update (username, avatar) on public.profiles to authenticated;

-- Plans : lecture des plans "live" par tous ; création par l'auteur ;
-- MAJ de ses propres plans tant qu'ils sont "live" — le WITH CHECK empêche de
-- réattribuer author, et le status dans le USING empêche de dé-bannir son plan.
drop policy if exists deals_read   on public.deals;
drop policy if exists deals_insert on public.deals;
drop policy if exists deals_update on public.deals;
create policy deals_read   on public.deals for select
  using (status = 'live' or author = (select auth.uid()));
-- Publication réservée aux comptes vérifiés : sur Supabase un compte anonyme
-- porte le rôle « authenticated » au même titre qu'un compte e-mail, donc
-- « to authenticated » seul laisserait publier n'importe quel visiteur.
create policy deals_insert on public.deals for insert
  to authenticated
  with check (author = (select auth.uid()) and public.is_verified_user());
create policy deals_update on public.deals for update
  to authenticated
  using      (author = (select auth.uid()) and status = 'live')
  with check (author = (select auth.uid()) and status = 'live');

-- Colonnes de scoring et de modération retirées au client : views et validations
-- sont maintenus par les triggers, verified et status par la modération, et le
-- WITH CHECK ci-dessus valide la ligne sans regarder les colonnes touchées.
-- author n'est absent que du grant UPDATE : il reste requis à l'insertion.
revoke insert, update on public.deals from anon, authenticated;
grant insert (author, cat, icon, title, price_now, price_old, discount, expires,
              description, tags, link, domain, image, video, steps)
  on public.deals to authenticated;
grant update (cat, icon, title, price_now, price_old, discount, expires,
              description, tags, link, domain, image, video, steps)
  on public.deals to authenticated;

-- Favoris / validations / alertes / notifications : chacun gère les siens
drop policy if exists fav_all      on public.favorites;
drop policy if exists val_all      on public.validations;
drop policy if exists alerts_all   on public.alerts;
drop policy if exists notif_read   on public.notifications;
drop policy if exists notif_update on public.notifications;
create policy fav_all    on public.favorites   for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy val_all    on public.validations for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy alerts_all on public.alerts      for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy notif_read   on public.notifications for select to authenticated
  using (user_id = (select auth.uid()));
create policy notif_update on public.notifications for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- Signalements : aucune écriture directe depuis le client, tout passe par
-- fn_report_deal. Sinon un seul compte insérerait trois lignes avec trois
-- reporter différents et déclencherait le ban à lui tout seul.
drop policy if exists reports_insert on public.reports;
revoke insert, update, delete on public.reports from anon, authenticated;

-- Codes d'accès : lecture publique (vérification du gate)
drop policy if exists codes_read on public.access_codes;
create policy codes_read on public.access_codes for select using (true);

-- Realtime sur les nouveaux plans (optionnel).
-- La publication supabase_realtime appartient à supabase_admin : selon le
-- projet, l'utilisateur du SQL Editor n'a pas le droit de la modifier. Comme
-- l'éditeur exécute tout le script dans UNE transaction, une erreur ici
-- annulerait la totalité du schéma — d'où ces trois cas rattrapés.
do $$
begin
  alter publication supabase_realtime add table public.deals;
exception
  when duplicate_object     then null;  -- déjà dans la publication
  when undefined_object     then raise notice 'publication supabase_realtime absente : realtime ignoré';
  when insufficient_privilege then raise notice 'droits insuffisants sur supabase_realtime : realtime ignoré, à activer depuis le dashboard';
end $$;
