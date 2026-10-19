-- =====================================================================
-- LAZERDECO — schéma Supabase v2 (PostgreSQL 15+)
-- Rôles personnalisables : chaque rôle porte une grille de droits
--   {"module": ["voir","creer","modifier","supprimer"]}.
-- « admin » a tous les droits ; « client » n'accède qu'à ses propres devis.
-- Toute la sécurité est appliquée par la base (Row Level Security).
-- À exécuter dans Supabase › SQL Editor, puis supabase-donnees.sql.
-- =====================================================================

create extension if not exists pgcrypto;

do $$ begin
  create type public.statut_devis as enum ('demande', 'devis_envoye', 'bat_envoye', 'valide', 'en_production', 'prete', 'livree', 'annulee');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.mode_paiement as enum ('virement', 'especes', 'carte', 'cheque', 'autre');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.type_paiement as enum ('acompte', 'solde', 'remboursement');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------
-- Modules et actions de l'espace de gestion
-- ---------------------------------------------------------------------
create or replace function public.modules_admin()
returns jsonb language sql immutable as $$
  select '{
    "statistiques": ["voir"],
    "produits":     ["voir", "creer", "modifier", "supprimer"],
    "univers":      ["voir", "creer", "modifier", "supprimer"],
    "machines":     ["voir", "creer", "modifier", "supprimer"],
    "promotions":   ["voir", "creer", "modifier", "supprimer"],
    "medias":       ["voir", "creer", "supprimer"],
    "devis":        ["voir", "creer", "modifier", "supprimer"],
    "production":   ["voir", "modifier"],
    "paiements":    ["voir", "creer", "modifier", "supprimer"],
    "clients":      ["voir", "modifier"],
    "pages":        ["voir", "creer", "modifier", "supprimer"],
    "textes":       ["voir", "modifier"],
    "parametres":   ["voir", "modifier"],
    "emails":       ["voir", "modifier"],
    "utilisateurs": ["voir", "creer", "modifier", "supprimer"],
    "roles":        ["voir", "creer", "modifier", "supprimer"],
    "journal":      ["voir"]
  }'::jsonb
$$;

create or replace function public.permissions_valides(p jsonb)
returns boolean language sql immutable as $$
  select jsonb_typeof(p) = 'object'
     and not exists (
       select 1 from jsonb_each(p) e
        where not (public.modules_admin() ? e.key)
           or jsonb_typeof(e.value) <> 'array'
           or exists (select 1 from jsonb_array_elements_text(e.value) a where not (public.modules_admin() -> e.key ? a)))
$$;

-- ---------------------------------------------------------------------
-- Rôles et comptes
-- ---------------------------------------------------------------------
create table if not exists public.roles (
  id           text primary key check (id ~ '^[a-z0-9_-]{2,30}$'),
  nom          text not null check (length(nom) between 2 and 40),
  description  text not null default '',
  permissions  jsonb not null default '{}'::jsonb check (public.permissions_valides(permissions)),
  systeme      boolean not null default false,
  equipe       boolean not null default true,
  ordre        int not null default 50
);
insert into public.roles (id, nom, description, systeme, equipe, ordre) values
  ('admin', 'Administrateur', 'Tous les droits sur l''ensemble du site.', true, true, 0),
  ('client', 'Client', 'Compte client du site : ses devis, BAT et commandes uniquement.', true, false, 99)
on conflict (id) do nothing;

create table if not exists public.profils (
  id          uuid primary key references auth.users (id) on delete cascade,
  email       text not null,
  nom         text not null default '',
  societe     text,
  telephone   text,
  role        text not null default 'client' references public.roles (id) on update cascade on delete restrict,
  actif       boolean not null default true,
  remise_pro  numeric(5, 2) not null default 0 check (remise_pro >= 0 and remise_pro <= 90),
  invite_le   timestamptz,
  cree_le     timestamptz not null default now()
);

create or replace function public.mon_role()
returns text language sql stable security definer set search_path = public as $$
  select role from public.profils where id = auth.uid() and actif
$$;

create or replace function public.est_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.mon_role() = 'admin', false)
$$;

create or replace function public.est_equipe()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select r.equipe from public.profils p join public.roles r on r.id = p.role where p.id = auth.uid() and p.actif), false)
$$;

create or replace function public.peut(module text, action text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select case when p.role = 'admin' then true else coalesce((r.permissions -> module) ? action, false) end
      from public.profils p join public.roles r on r.id = p.role
     where p.id = auth.uid() and p.actif), false)
$$;

-- Appel depuis l'éditeur SQL, une clé de service ou une fonction interne : pas de restriction applicative.
create or replace function public.appel_systeme()
returns boolean language sql stable as $$
  select current_user not in ('anon', 'authenticated')
$$;

create or replace function public.nouveau_profil()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profils (id, email, nom, societe, telephone)
  values (new.id, coalesce(new.email, ''),
          coalesce(new.raw_user_meta_data ->> 'nom', ''),
          nullif(new.raw_user_meta_data ->> 'societe', ''),
          nullif(new.raw_user_meta_data ->> 'telephone', ''))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists t_nouveau_profil on auth.users;
create trigger t_nouveau_profil after insert on auth.users
  for each row execute function public.nouveau_profil();

create or replace function public.garde_profil()
returns trigger language plpgsql as $$
begin
  if public.appel_systeme() then return new; end if;
  if new.id is distinct from old.id or new.email is distinct from old.email or new.invite_le is distinct from old.invite_le then
    raise exception 'L''identifiant et l''e-mail d''un compte ne se modifient pas ici' using errcode = '42501';
  end if;
  if new.role is distinct from old.role or new.actif is distinct from old.actif then
    if not public.peut('utilisateurs', 'modifier') then
      raise exception 'Droit « Utilisateurs › modifier » requis pour changer un rôle ou désactiver un compte' using errcode = '42501';
    end if;
    if old.id = auth.uid() then
      raise exception 'Vous ne pouvez pas modifier votre propre rôle ni désactiver votre propre compte' using errcode = '42501';
    end if;
    if (new.role = 'admin' or old.role = 'admin') and not public.est_admin() then
      raise exception 'Seul un administrateur peut attribuer ou retirer le rôle Administrateur' using errcode = '42501';
    end if;
  end if;
  if new.remise_pro is distinct from old.remise_pro and not public.peut('clients', 'modifier') then
    raise exception 'Droit « Clients › modifier » requis pour fixer un tarif professionnel' using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists t_garde_profil on public.profils;
create trigger t_garde_profil before update on public.profils
  for each row execute function public.garde_profil();

create or replace function public.garde_role()
returns trigger language plpgsql as $$
begin
  if public.appel_systeme() then return coalesce(new, old); end if;
  if tg_op = 'DELETE' then
    if old.systeme then raise exception 'Le rôle « % » est un rôle système et ne peut pas être supprimé', old.nom using errcode = '42501'; end if;
    return old;
  end if;
  if tg_op = 'INSERT' then new.systeme := false; end if;
  if tg_op = 'UPDATE' then
    if old.systeme and (new.id <> old.id or new.permissions <> old.permissions or new.equipe <> old.equipe or not new.systeme) then
      raise exception 'Les droits du rôle « % » sont fixes', old.nom using errcode = '42501';
    end if;
    if not old.systeme then new.systeme := false; end if;
    if not public.est_admin() and old.id = public.mon_role() then
      raise exception 'Vous ne pouvez pas modifier les droits de votre propre rôle' using errcode = '42501';
    end if;
  end if;
  if not public.est_admin() and ((new.permissions ? 'roles') or (new.permissions ? 'utilisateurs')) then
    raise exception 'Seul un administrateur peut accorder les droits « Utilisateurs » et « Rôles »' using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists t_garde_role on public.roles;
create trigger t_garde_role before insert or update or delete on public.roles
  for each row execute function public.garde_role();

-- ---------------------------------------------------------------------
-- Catalogue
-- ---------------------------------------------------------------------
create table if not exists public.categories (
  id        text primary key check (id ~ '^[a-z0-9-]{2,40}$'),
  nom       text not null check (length(nom) between 2 and 80),
  accroche  text not null default '',
  couleur   text not null default 'blu' check (couleur in ('mag', 'cya', 'ora', 'blu')),
  ordre     int not null default 0,
  actif     boolean not null default true
);

create table if not exists public.techniques (
  id          text primary key check (id ~ '^[a-z0-9-]{2,20}$'),
  nom         text not null,
  detail      text not null default '',
  delai_jours int not null default 3 check (delai_jours between 0 and 60),
  actif       boolean not null default true,
  ordre       int not null default 0
);

create or replace function public.paliers_valides(q int[], p numeric[])
returns boolean language sql immutable as $$
  select cardinality(q) = cardinality(p)
     and cardinality(q) between 2 and 6
     and q[1] >= 1
     and not exists (select 1 from generate_series(2, cardinality(q)) i where q[i] <= q[i - 1] or p[i] > p[i - 1])
     and not exists (select 1 from unnest(p) v where v <= 0)
$$;

create table if not exists public.produits (
  ref          text primary key check (ref ~ '^[A-Z]-[0-9]{2,3}$'),
  nom          text not null check (length(nom) between 2 and 80),
  categorie    text not null references public.categories (id) on update cascade,
  techniques   text[] not null check (cardinality(techniques) > 0),
  description  text not null default '' check (length(description) <= 400),
  quantites    int[] not null,
  prix         numeric(10, 2)[] not null,
  badge        text check (badge in ('Best-seller', 'Nouveau')),
  emplacement  numeric(10, 2) check (emplacement is null or emplacement > 0),
  a_partir     boolean not null default false,
  image        text,
  forme        text,
  teinte       text check (teinte is null or teinte ~ '^#[0-9A-Fa-f]{6}$'),
  actif        boolean not null default true,
  ordre        int not null default 0,
  maj_le       timestamptz not null default now(),
  maj_par      uuid,
  constraint paliers_coherents check (public.paliers_valides(quantites, prix))
);
create index if not exists produits_categorie on public.produits (categorie, ordre);

create or replace function public.controle_produit()
returns trigger language plpgsql as $$
begin
  if exists (select 1 from unnest(new.techniques) t where t not in (select id from public.techniques)) then
    raise exception 'Machine inconnue dans %', new.techniques using errcode = '23503';
  end if;
  new.maj_le := now();
  new.maj_par := auth.uid();
  return new;
end $$;

drop trigger if exists t_controle_produit on public.produits;
create trigger t_controle_produit before insert or update on public.produits
  for each row execute function public.controle_produit();

create or replace function public.garde_technique()
returns trigger language plpgsql security definer set search_path = public as $$
declare n int;
begin
  select count(*) into n from public.produits where old.id = any (techniques);
  if n > 0 then
    raise exception 'Cette machine est utilisée par % produit(s) : retirez-la d''abord des fiches ou masquez-la', n using errcode = '23503';
  end if;
  return old;
end $$;

drop trigger if exists t_garde_technique on public.techniques;
create trigger t_garde_technique before delete on public.techniques
  for each row execute function public.garde_technique();

-- ---------------------------------------------------------------------
-- Promotions
-- ---------------------------------------------------------------------
create table if not exists public.promotions (
  id       bigint generated always as identity primary key,
  nom      text not null check (length(nom) between 2 and 80),
  pct      numeric(5, 2) not null check (pct > 0 and pct <= 90),
  produit  text references public.produits (ref) on delete cascade on update cascade,
  univers  text references public.categories (id) on delete cascade on update cascade,
  debut    date,
  fin      date,
  actif    boolean not null default true,
  cree_le  timestamptz not null default now(),
  check (fin is null or debut is null or fin >= debut)
);

create table if not exists public.codes_promo (
  code              text primary key check (code ~ '^[A-Z0-9_-]{3,30}$'),
  description       text not null default '',
  type              text not null check (type in ('pct', 'montant')),
  valeur            numeric(10, 2) not null check (valeur > 0),
  minimum_ht        numeric(10, 2) not null default 0 check (minimum_ht >= 0),
  debut             date,
  fin               date,
  max_utilisations  int check (max_utilisations is null or max_utilisations > 0),
  produit           text references public.produits (ref) on delete cascade on update cascade,
  univers           text references public.categories (id) on delete cascade on update cascade,
  actif             boolean not null default true,
  cree_le           timestamptz not null default now(),
  check (type <> 'pct' or valeur <= 90),
  check (fin is null or debut is null or fin >= debut)
);

create or replace function public.en_cours(actif boolean, debut date, fin date)
returns boolean language sql stable as $$
  select actif and (debut is null or debut <= current_date) and (fin is null or fin >= current_date)
$$;

create or replace function public.promo_pct(p_ref text)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(max(pr.pct), 0)
    from public.promotions pr join public.produits p on p.ref = p_ref
   where public.en_cours(pr.actif, pr.debut, pr.fin)
     and (pr.produit is null or pr.produit = p.ref)
     and (pr.univers is null or pr.univers = p.categorie)
$$;

-- ---------------------------------------------------------------------
-- Contenus du site
-- ---------------------------------------------------------------------
create table if not exists public.textes (
  cle     text primary key check (cle ~ '^[a-z0-9_]{2,60}$'),
  valeur  text not null default '',
  aide    text not null default '',
  maj_le  timestamptz not null default now()
);

create table if not exists public.parametres (
  cle     text primary key check (cle ~ '^[a-z0-9_]{2,60}$'),
  valeur  jsonb not null,
  aide    text not null default '',
  maj_le  timestamptz not null default now()
);

create table if not exists public.pages (
  slug             text primary key check (slug ~ '^[a-z0-9-]{2,60}$'),
  titre            text not null check (length(titre) between 2 and 120),
  contenu          text not null default '',
  type             text not null default 'libre' check (type in ('legale', 'libre')),
  seo_titre        text check (length(seo_titre) <= 70),
  seo_description  text check (length(seo_description) <= 300),
  publie           boolean not null default true,
  dans_pied        boolean not null default true,
  ordre            int not null default 0,
  maj_le           timestamptz not null default now()
);

create or replace function public.param(cle_ text)
returns jsonb language sql stable security definer set search_path = public as $$
  select valeur from public.parametres where cle = cle_
$$;

-- ---------------------------------------------------------------------
-- Calcul des prix (identique à tarifs.js)
-- ---------------------------------------------------------------------
create or replace function public.calcul_prix(p_ref text, p_q int, p_empl boolean, p_express boolean, p_remise numeric)
returns table (unitaire numeric, promo numeric, minimum int)
language plpgsql stable security definer set search_path = public as $$
declare
  p public.produits;
  i int;
  u numeric := null;
  pct numeric;
begin
  select * into p from public.produits where ref = p_ref;
  if not found then raise exception 'Produit inconnu : %', p_ref using errcode = '23503'; end if;
  for i in 1 .. cardinality(p.quantites) loop
    if p_q >= p.quantites[i] then u := p.prix[i]; end if;
  end loop;
  if u is null then
    unitaire := null; promo := 0; minimum := p.quantites[1]; return next; return;
  end if;
  pct := public.promo_pct(p_ref);
  if pct > 0 then u := u * (1 - pct / 100); end if;
  if p_empl and p.emplacement is not null then u := u + p.emplacement; end if;
  if p_express then u := u * (1 + coalesce((public.param('express'))::numeric, 0.2)); end if;
  if coalesce(p_remise, 0) > 0 then u := u * (1 - p_remise / 100); end if;
  unitaire := round(u, 2); promo := pct; minimum := p.quantites[1];
  return next;
end $$;

-- Remise d'un code promo sur un ensemble de lignes [{ref, total}] (identique à TARIF.code).
create or replace function public.remise_code(p_code text, p_lignes jsonb, p_exclure bigint default null)
returns table (valide boolean, remise numeric, message text)
language plpgsql stable security definer set search_path = public as $$
declare
  c public.codes_promo;
  elig numeric;
  n int;
begin
  valide := false; remise := 0;
  select * into c from public.codes_promo where code = upper(trim(p_code));
  if not found then message := 'Ce code promo n''existe pas.'; return next; return; end if;
  if not public.en_cours(c.actif, c.debut, c.fin) then message := 'Ce code promo n''est pas valable actuellement.'; return next; return; end if;
  if c.max_utilisations is not null then
    select count(*) into n from public.devis where code_promo = c.code and statut <> 'annulee' and id is distinct from p_exclure;
    if n >= c.max_utilisations then message := 'Ce code promo a atteint son nombre maximal d''utilisations.'; return next; return; end if;
  end if;
  select coalesce(sum((l ->> 'total')::numeric), 0) into elig
    from jsonb_array_elements(p_lignes) l join public.produits p on p.ref = l ->> 'ref'
   where (c.produit is null or p.ref = c.produit) and (c.univers is null or p.categorie = c.univers);
  if elig <= 0 then message := 'Ce code ne s''applique à aucun produit de votre sélection.'; return next; return; end if;
  if c.minimum_ht > elig then message := 'Ce code s''applique dès ' || replace(to_char(c.minimum_ht, 'FM999990.00'), '.', ',') || ' € HT d''achat.'; return next; return; end if;
  valide := true;
  remise := case when c.type = 'pct' then round(elig * c.valeur / 100, 2) else round(least(c.valeur, elig), 2) end;
  message := 'Remise appliquée';
  return next;
end $$;

-- ---------------------------------------------------------------------
-- Devis, commandes, BAT, paiements
-- ---------------------------------------------------------------------
create table if not exists public.devis (
  id               bigint generated always as identity primary key,
  numero           text unique,
  client           uuid not null references public.profils (id) on delete restrict,
  destination      text not null check (destination in ('mq-retrait', 'mq-livraison', 'gp', 'gf')),
  statut           public.statut_devis not null default 'demande',
  message          text check (length(message) <= 2000),
  note_interne     text,
  code_promo       text,
  code_valide      boolean not null default false,
  taux_tva         numeric(5, 4) not null default 0,
  frais_livraison  numeric(10, 2) not null default 0 check (frais_livraison >= 0),
  sous_total_ht    numeric(12, 2) not null default 0,
  remise_code      numeric(12, 2) not null default 0,
  total_ht         numeric(12, 2) not null default 0,
  total_ttc        numeric(12, 2) generated always as (round((total_ht + frais_livraison) * (1 + taux_tva), 2)) stored,
  cree_le          timestamptz not null default now(),
  maj_le           timestamptz not null default now()
);
create index if not exists devis_client on public.devis (client, cree_le desc);
create index if not exists devis_statut on public.devis (statut, cree_le desc);

create table if not exists public.devis_lignes (
  id             bigint generated always as identity primary key,
  devis          bigint not null references public.devis (id) on delete cascade,
  ref            text not null references public.produits (ref) on update cascade,
  quantite       int not null check (quantite between 1 and 100000),
  emplacement    boolean not null default false,
  express        boolean not null default false,
  note           text check (length(note) <= 500),
  fichier        text check (length(fichier) <= 200),
  prix_force     boolean not null default false,
  promo_pct      numeric(5, 2) not null default 0,
  remise_pro     numeric(5, 2) not null default 0,
  prix_unitaire  numeric(10, 2) not null default 0,
  total          numeric(12, 2) not null default 0,
  statut_prod    text not null default 'a_faire' check (statut_prod in ('a_faire', 'en_cours', 'termine'))
);
create index if not exists lignes_devis on public.devis_lignes (devis);

create table if not exists public.bats (
  id                 bigint generated always as identity primary key,
  devis              bigint not null references public.devis (id) on delete cascade,
  version            int not null default 0,
  fichier            text not null check (length(fichier) <= 300),
  nom_fichier        text,
  message            text check (length(message) <= 1000),
  statut             text not null default 'en_attente' check (statut in ('en_attente', 'valide', 'correction', 'remplace')),
  commentaire_client text check (length(commentaire_client) <= 1000),
  depose_par         uuid default auth.uid(),
  depose_le          timestamptz not null default now(),
  repondu_le         timestamptz,
  unique (devis, version)
);

create table if not exists public.paiements (
  id             bigint generated always as identity primary key,
  devis          bigint not null references public.devis (id) on delete restrict,
  type           public.type_paiement not null default 'acompte',
  mode           public.mode_paiement not null,
  montant        numeric(12, 2) not null check (montant > 0),
  date_paiement  date not null default current_date,
  reference      text check (length(reference) <= 120),
  saisi_par      uuid default auth.uid(),
  cree_le        timestamptz not null default now()
);
create index if not exists paiements_devis on public.paiements (devis);

create table if not exists public.emails (
  id           bigint generated always as identity primary key,
  cree_le      timestamptz not null default now(),
  type         text not null,
  destinataire text not null,
  sujet        text not null,
  corps        text not null,
  devis        bigint references public.devis (id) on delete set null,
  statut       text not null default 'en_attente' check (statut in ('en_attente', 'envoye', 'erreur', 'annule')),
  erreur       text,
  tentatives   int not null default 0,
  envoye_le    timestamptz
);
create index if not exists emails_statut on public.emails (statut, id);

create or replace function public.tva_destination(dest text)
returns numeric language sql stable as $$
  select coalesce((public.param('tva') ->> case dest when 'gp' then 'Guadeloupe' when 'gf' then 'Guyane' else 'Martinique' end)::numeric, 0)
$$;

create or replace function public.prepare_devis()
returns trigger language plpgsql as $$
declare staff boolean := public.appel_systeme() or public.peut('devis', 'modifier') or public.peut('devis', 'creer');
begin
  if tg_op = 'INSERT' then
    if not staff then
      new.client := auth.uid();
      new.statut := 'demande';
      new.note_interne := null;
      new.frais_livraison := 0;
    end if;
    new.numero := 'D' || to_char(now(), 'YY') || '-' || lpad(new.id::text, 5, '0');
    new.sous_total_ht := 0; new.remise_code := 0; new.total_ht := 0; new.code_valide := false;
  else
    new.numero := old.numero;
    new.client := old.client;
    new.cree_le := old.cree_le;
  end if;
  new.code_promo := nullif(upper(trim(new.code_promo)), '');
  new.taux_tva := public.tva_destination(new.destination);
  new.maj_le := now();
  return new;
end $$;

drop trigger if exists t_prepare_devis on public.devis;
create trigger t_prepare_devis before insert or update on public.devis
  for each row execute function public.prepare_devis();

-- Totaux calculés uniquement par le système.
create or replace function public.garde_total()
returns trigger language plpgsql as $$
begin
  if tg_op = 'UPDATE' and pg_trigger_depth() < 2 then
    new.sous_total_ht := old.sous_total_ht; new.remise_code := old.remise_code;
    new.total_ht := old.total_ht; new.code_valide := old.code_valide;
  end if;
  return new;
end $$;

drop trigger if exists t_garde_total on public.devis;
create trigger t_garde_total before update on public.devis
  for each row execute function public.garde_total();

create or replace function public.garde_devis_client()
returns trigger language plpgsql as $$
begin
  if public.appel_systeme() or public.peut('devis', 'modifier') then return new; end if;
  if (new.destination, new.message, new.frais_livraison, new.note_interne, new.code_promo) is distinct from
     (old.destination, old.message, old.frais_livraison, old.note_interne, old.code_promo) then
    raise exception 'Une demande envoyée ne peut plus être modifiée : contactez l''atelier' using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists t_garde_devis_client on public.devis;
create trigger t_garde_devis_client before update on public.devis
  for each row execute function public.garde_devis_client();

create or replace function public.remise_client(p_devis bigint)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(p.remise_pro, 0) from public.devis d join public.profils p on p.id = d.client where d.id = p_devis
$$;

create or replace function public.garde_ligne()
returns trigger language plpgsql as $$
begin
  if public.appel_systeme() or public.peut('devis', 'modifier') then return new; end if;
  if tg_op = 'UPDATE' and public.peut('production', 'modifier') then
    if (new.devis, new.ref, new.quantite, new.emplacement, new.express, new.note, new.fichier, new.prix_force, new.prix_unitaire) is distinct from
       (old.devis, old.ref, old.quantite, old.emplacement, old.express, old.note, old.fichier, old.prix_force, old.prix_unitaire) then
      raise exception 'Le profil Production ne peut modifier que l''avancement des lignes' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists t_garde_ligne on public.devis_lignes;
create trigger t_garde_ligne before insert or update on public.devis_lignes
  for each row execute function public.garde_ligne();

create or replace function public.prix_ligne()
returns trigger language plpgsql as $$
declare
  p public.produits;
  c record;
  staff boolean := public.appel_systeme() or public.peut('devis', 'modifier');
  rp numeric;
begin
  if tg_op = 'UPDATE' and (new.ref, new.quantite, new.emplacement, new.express, new.prix_force) is not distinct from
                          (old.ref, old.quantite, old.emplacement, old.express, old.prix_force)
     and (not new.prix_force or new.prix_unitaire = old.prix_unitaire) then
    new.prix_unitaire := old.prix_unitaire; new.total := old.total; new.promo_pct := old.promo_pct; new.remise_pro := old.remise_pro;
    return new;
  end if;
  select * into p from public.produits where ref = new.ref;
  if not found or (not p.actif and not staff) then
    raise exception 'Produit indisponible : %', new.ref using errcode = '23503';
  end if;
  if new.prix_force and staff then
    new.promo_pct := 0; new.remise_pro := 0;
  else
    new.prix_force := false;
    rp := public.remise_client(new.devis);
    select * into c from public.calcul_prix(new.ref, new.quantite, new.emplacement, new.express, rp);
    if c.unitaire is null then
      raise exception 'Quantité minimale pour % : % exemplaires', p.ref, c.minimum using errcode = '23514';
    end if;
    if not (new.emplacement and p.emplacement is not null) then new.emplacement := false; end if;
    new.prix_unitaire := c.unitaire; new.promo_pct := c.promo; new.remise_pro := rp;
  end if;
  new.prix_unitaire := round(new.prix_unitaire, 2);
  new.total := round(new.prix_unitaire * new.quantite, 2);
  return new;
end $$;

drop trigger if exists t_prix_ligne on public.devis_lignes;
create trigger t_prix_ligne before insert or update on public.devis_lignes
  for each row execute function public.prix_ligne();

create or replace function public.recalculer_devis(d bigint)
returns void language plpgsql security definer set search_path = public as $$
declare
  sous numeric;
  code text;
  v_remise numeric := 0;
  v_valide boolean := false;
begin
  select coalesce(sum(total), 0) into sous from public.devis_lignes where devis = d;
  select code_promo into code from public.devis where id = d;
  if code is not null then
    select rc.remise, rc.valide into v_remise, v_valide from public.remise_code(code,
      (select coalesce(jsonb_agg(jsonb_build_object('ref', ref, 'total', total)), '[]'::jsonb) from public.devis_lignes where devis = d), d) rc;
  end if;
  update public.devis
     set sous_total_ht = sous,
         remise_code = coalesce(v_remise, 0),
         code_valide = coalesce(v_valide, false),
         total_ht = sous - coalesce(v_remise, 0)
   where id = d;
end $$;

create or replace function public.total_devis()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.recalculer_devis(coalesce(new.devis, old.devis));
  return null;
end $$;

drop trigger if exists t_total_devis on public.devis_lignes;
create trigger t_total_devis after insert or update or delete on public.devis_lignes
  for each row execute function public.total_devis();

create or replace function public.code_modifie()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.recalculer_devis(new.id);
  return null;
end $$;

drop trigger if exists t_code_modifie on public.devis;
create trigger t_code_modifie after update of code_promo on public.devis
  for each row when (old.code_promo is distinct from new.code_promo) execute function public.code_modifie();

-- Avancement de la production → statut de la commande.
create or replace function public.avancement_production()
returns trigger language plpgsql security definer set search_path = public as $$
declare d public.devis; n_total int; n_fini int; n_lance int;
begin
  select * into d from public.devis where id = new.devis;
  select count(*), count(*) filter (where statut_prod = 'termine'), count(*) filter (where statut_prod <> 'a_faire')
    into n_total, n_fini, n_lance from public.devis_lignes where devis = new.devis;
  if n_total > 0 and n_fini = n_total and d.statut in ('valide', 'en_production') then
    update public.devis set statut = 'prete' where id = d.id;
  elsif n_lance > 0 and d.statut = 'valide' then
    update public.devis set statut = 'en_production' where id = d.id;
  end if;
  return null;
end $$;

drop trigger if exists t_avancement on public.devis_lignes;
create trigger t_avancement after update of statut_prod on public.devis_lignes
  for each row when (old.statut_prod is distinct from new.statut_prod) execute function public.avancement_production();

-- ---------------------------------------------------------------------
-- E-mails automatiques (file d'attente envoyée par la fonction envoyer-emails)
-- ---------------------------------------------------------------------
create or replace function public.libelle_statut(s text)
returns text language sql immutable as $$
  select case s when 'demande' then 'Demande reçue' when 'devis_envoye' then 'Devis envoyé' when 'bat_envoye' then 'BAT envoyé'
    when 'valide' then 'Validée' when 'en_production' then 'En production' when 'prete' then 'Prête' when 'livree' then 'Livrée'
    when 'annulee' then 'Annulée' else s end
$$;

create or replace function public.notifier(p_type text, p_devis bigint, p_extra jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  m jsonb := public.param('modeles_emails') -> p_type;
  d public.devis;
  c public.profils;
  v jsonb;
  sujet text;
  corps text;
  k text;
  val text;
  dest text;
  site text := coalesce(public.param('site_url') #>> '{}', '');
begin
  if m is null or coalesce((m ->> 'actif')::boolean, true) = false then return; end if;
  select * into d from public.devis where id = p_devis;
  if not found then return; end if;
  select * into c from public.profils where id = d.client;
  v := jsonb_build_object(
    'numero', d.numero, 'client', coalesce(nullif(c.nom, ''), c.email), 'societe', coalesce(c.societe, ''),
    'statut', public.libelle_statut(d.statut::text),
    'total_ttc', replace(to_char(d.total_ttc, 'FM999999990.00'), '.', ',') || ' €',
    'marque', coalesce(public.param('marque') #>> '{}', 'LAZR DECO'),
    'lien_client', site || '#/compte', 'lien_gestion', site || 'admin.html#/commandes/' || d.id) || coalesce(p_extra, '{}'::jsonb);
  sujet := m ->> 'sujet'; corps := m ->> 'corps';
  for k, val in select key, value from jsonb_each_text(v) loop
    sujet := replace(sujet, '{{' || k || '}}', coalesce(val, ''));
    corps := replace(corps, '{{' || k || '}}', coalesce(val, ''));
  end loop;
  if coalesce(m ->> 'pour', 'client') = 'equipe' then
    for dest in select jsonb_array_elements_text(coalesce(public.param('email_equipe'), '[]'::jsonb)) loop
      if dest ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
        insert into public.emails (type, destinataire, sujet, corps, devis) values (p_type, dest, sujet, corps, d.id);
      end if;
    end loop;
  elsif c.actif and c.email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    insert into public.emails (type, destinataire, sujet, corps, devis) values (p_type, c.email, sujet, corps, d.id);
  end if;
end $$;

create or replace function public.notif_statut()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.statut in ('devis_envoye', 'valide', 'en_production', 'prete', 'livree')
     or (new.statut = 'annulee' and auth.uid() is distinct from new.client) then
    perform public.notifier('statut', new.id);
  end if;
  return null;
end $$;

drop trigger if exists t_notif_statut on public.devis;
create trigger t_notif_statut after update of statut on public.devis
  for each row when (old.statut is distinct from new.statut) execute function public.notif_statut();

create or replace function public.notif_paiement()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.type <> 'remboursement' then
    perform public.notifier('paiement', new.devis, jsonb_build_object('montant', replace(to_char(new.montant, 'FM999999990.00'), '.', ',') || ' €'));
  end if;
  return null;
end $$;

drop trigger if exists t_notif_paiement on public.paiements;
create trigger t_notif_paiement after insert on public.paiements
  for each row execute function public.notif_paiement();

-- BAT : numérotation, remplacement de la version précédente, statut de la commande.
create or replace function public.prepare_bat()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.version := coalesce((select max(version) from public.bats where devis = new.devis), 0) + 1;
  new.statut := 'en_attente'; new.commentaire_client := null; new.repondu_le := null;
  new.depose_par := auth.uid(); new.depose_le := now();
  update public.bats set statut = 'remplace' where devis = new.devis and statut = 'en_attente';
  return new;
end $$;

drop trigger if exists t_prepare_bat on public.bats;
create trigger t_prepare_bat before insert on public.bats
  for each row execute function public.prepare_bat();

create or replace function public.bat_depose()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.devis set statut = 'bat_envoye' where id = new.devis and statut in ('demande', 'devis_envoye', 'bat_envoye');
  perform public.notifier('bat', new.devis, jsonb_build_object('version', new.version::text));
  return null;
end $$;

drop trigger if exists t_bat_depose on public.bats;
create trigger t_bat_depose after insert on public.bats
  for each row execute function public.bat_depose();

-- Réponse du client à un BAT.
create or replace function public.repondre_bat(p_bat bigint, p_decision text, p_commentaire text default null)
returns public.bats language plpgsql security definer set search_path = public as $$
declare b public.bats; d public.devis;
begin
  select * into b from public.bats where id = p_bat;
  if not found then raise exception 'BAT introuvable' using errcode = 'P0002'; end if;
  select * into d from public.devis where id = b.devis;
  if d.client is distinct from auth.uid() then raise exception 'Ce BAT ne vous concerne pas' using errcode = '42501'; end if;
  if b.statut <> 'en_attente' then raise exception 'Ce BAT a déjà reçu une réponse' using errcode = '23514'; end if;
  if p_decision not in ('valide', 'correction') then raise exception 'Réponse invalide' using errcode = '22023'; end if;
  if p_decision = 'correction' and length(trim(coalesce(p_commentaire, ''))) < 3 then
    raise exception 'Décrivez la correction souhaitée' using errcode = '23514';
  end if;
  update public.bats set statut = p_decision, commentaire_client = nullif(trim(p_commentaire), ''), repondu_le = now()
   where id = p_bat returning * into b;
  if p_decision = 'valide' and d.statut in ('demande', 'devis_envoye', 'bat_envoye') then
    update public.devis set statut = 'valide' where id = d.id;
  end if;
  perform public.notifier('bat_reponse', d.id, jsonb_build_object('version', b.version::text,
    'decision', case p_decision when 'valide' then 'validé' else 'à corriger' end, 'commentaire', coalesce(b.commentaire_client, '')));
  return b;
end $$;

-- Alerte « nouvelle demande » : seulement par le client lui-même, une fois, juste après l'envoi.
create or replace function public.notifier_nouvelle_demande(p_devis bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.devis d where d.id = p_devis and d.client = auth.uid() and d.statut = 'demande'
              and d.cree_le > now() - interval '2 minutes')
     and not exists (select 1 from public.emails e where e.devis = p_devis and e.type = 'nouvelle_demande') then
    perform public.notifier('nouvelle_demande', p_devis);
  end if;
end $$;

-- Envoi d'une demande par un client : devis et lignes en une seule opération.
create or replace function public.soumettre_devis(p_destination text, p_message text, p_code text, p_lignes jsonb)
returns public.devis language plpgsql security invoker set search_path = public as $$
declare d public.devis;
begin
  if jsonb_typeof(p_lignes) <> 'array' or jsonb_array_length(p_lignes) = 0 then
    raise exception 'Votre sélection est vide' using errcode = '22023';
  end if;
  insert into public.devis (client, destination, message, code_promo)
  values (auth.uid(), p_destination, nullif(trim(p_message), ''), nullif(upper(trim(p_code)), ''))
  returning * into d;
  insert into public.devis_lignes (devis, ref, quantite, emplacement, express, note, fichier)
  select d.id, x ->> 'ref', (x ->> 'quantite')::int, coalesce((x ->> 'emplacement')::boolean, false),
         coalesce((x ->> 'express')::boolean, false), nullif(x ->> 'note', ''), nullif(x ->> 'fichier', '')
    from jsonb_array_elements(p_lignes) x;
  perform public.notifier_nouvelle_demande(d.id);
  select * into d from public.devis where id = d.id;
  return d;
end $$;

-- Vérification d'un code promo avant envoi (aucune écriture).
create or replace function public.verifier_code(p_code text, p_lignes jsonb)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  rp numeric := coalesce((select remise_pro from public.profils where id = auth.uid()), 0);
  lignes jsonb := '[]'::jsonb;
  x jsonb;
  c record;
  r record;
begin
  if auth.uid() is null then raise exception 'Connectez-vous pour utiliser un code promo' using errcode = '42501'; end if;
  for x in select * from jsonb_array_elements(p_lignes) loop
    select * into c from public.calcul_prix(x ->> 'ref', (x ->> 'quantite')::int, coalesce((x ->> 'emplacement')::boolean, false),
                                            coalesce((x ->> 'express')::boolean, false), rp);
    if c.unitaire is not null then
      lignes := lignes || jsonb_build_object('ref', x ->> 'ref', 'total', round(c.unitaire * (x ->> 'quantite')::int, 2));
    end if;
  end loop;
  select * into r from public.remise_code(p_code, lignes);
  return jsonb_build_object('ok', r.valide, 'remise', r.remise, 'message', r.message);
end $$;

-- Suivi : montant payé et reste à payer (respecte les droits de l'appelant).
drop view if exists public.suivi_devis;
create view public.suivi_devis with (security_invoker = true) as
select d.*,
       p.nom as client_nom, p.societe as client_societe, p.email as client_email, p.telephone as client_telephone,
       coalesce(sum(case when pa.type = 'remboursement' then -pa.montant else pa.montant end), 0)::numeric(12, 2) as paye,
       (d.total_ttc - coalesce(sum(case when pa.type = 'remboursement' then -pa.montant else pa.montant end), 0))::numeric(12, 2) as reste
  from public.devis d
  join public.profils p on p.id = d.client
  left join public.paiements pa on pa.devis = d.id
 group by d.id, p.id;

-- ---------------------------------------------------------------------
-- Journal des actions
-- ---------------------------------------------------------------------
create table if not exists public.journal (
  id         bigint generated always as identity primary key,
  quand      timestamptz not null default now(),
  qui        uuid,
  qui_email  text,
  role       text,
  table_nom  text not null,
  action     text not null,
  cle        text,
  avant      jsonb,
  apres      jsonb
);
create index if not exists journal_quand on public.journal (quand desc);

create or replace function public.journaliser()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  a jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  b jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  k text := coalesce(b, a) ->> tg_argv[0];
begin
  if tg_op = 'UPDATE' and a = b then return null; end if;
  insert into public.journal (qui, qui_email, role, table_nom, action, cle, avant, apres)
  values (auth.uid(), (select email from public.profils where id = auth.uid()), public.mon_role(),
          tg_table_name, lower(tg_op), k, a, b);
  return null;
end $$;

do $$
declare t record;
begin
  for t in select * from (values ('produits', 'ref'), ('categories', 'id'), ('techniques', 'id'), ('textes', 'cle'),
                                 ('parametres', 'cle'), ('profils', 'email'), ('roles', 'id'), ('devis', 'numero'),
                                 ('paiements', 'id'), ('promotions', 'nom'), ('codes_promo', 'code'), ('pages', 'slug'),
                                 ('bats', 'id')) v(tab, k)
  loop
    execute format('drop trigger if exists t_journal on public.%I', t.tab);
    execute format('create trigger t_journal after insert or update or delete on public.%I for each row execute function public.journaliser(%L)', t.tab, t.k);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Sécurité par ligne (RLS)
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['roles', 'profils', 'categories', 'techniques', 'produits', 'promotions', 'codes_promo', 'textes',
                           'parametres', 'pages', 'devis', 'devis_lignes', 'bats', 'paiements', 'emails', 'journal'] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

do $$
declare r record;
begin
  for r in select policyname, tablename from pg_policies where schemaname = 'public' loop
    execute format('drop policy %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

-- Rôles
create policy roles_lire on public.roles for select to authenticated using (public.est_equipe());
create policy roles_creer on public.roles for insert to authenticated with check (public.peut('roles', 'creer'));
create policy roles_modifier on public.roles for update to authenticated using (public.peut('roles', 'modifier')) with check (public.peut('roles', 'modifier'));
create policy roles_supprimer on public.roles for delete to authenticated using (public.peut('roles', 'supprimer') and not systeme);

-- Profils
create policy profils_lire on public.profils for select to authenticated
  using (id = auth.uid() or public.peut('utilisateurs', 'voir') or public.peut('clients', 'voir') or public.peut('devis', 'voir')
         or public.peut('statistiques', 'voir') or public.peut('production', 'voir'));
create policy profils_modifier on public.profils for update to authenticated
  using (id = auth.uid() or public.peut('utilisateurs', 'modifier') or public.peut('clients', 'modifier'))
  with check (id = auth.uid() or public.peut('utilisateurs', 'modifier') or public.peut('clients', 'modifier'));

-- Catalogue
create policy categories_lire on public.categories for select to anon, authenticated using (actif or public.est_equipe());
create policy categories_creer on public.categories for insert to authenticated with check (public.peut('univers', 'creer'));
create policy categories_modifier on public.categories for update to authenticated using (public.peut('univers', 'modifier')) with check (public.peut('univers', 'modifier'));
create policy categories_supprimer on public.categories for delete to authenticated using (public.peut('univers', 'supprimer'));

create policy techniques_lire on public.techniques for select to anon, authenticated using (actif or public.est_equipe());
create policy techniques_creer on public.techniques for insert to authenticated with check (public.peut('machines', 'creer'));
create policy techniques_modifier on public.techniques for update to authenticated using (public.peut('machines', 'modifier')) with check (public.peut('machines', 'modifier'));
create policy techniques_supprimer on public.techniques for delete to authenticated using (public.peut('machines', 'supprimer'));

create policy produits_lire on public.produits for select to anon, authenticated using (actif or public.est_equipe());
create policy produits_creer on public.produits for insert to authenticated with check (public.peut('produits', 'creer'));
create policy produits_modifier on public.produits for update to authenticated using (public.peut('produits', 'modifier')) with check (public.peut('produits', 'modifier'));
create policy produits_supprimer on public.produits for delete to authenticated using (public.peut('produits', 'supprimer'));

-- Promotions : les promotions en cours sont publiques (prix barrés), les codes restent internes.
create policy promotions_lire on public.promotions for select to anon, authenticated
  using (public.en_cours(actif, debut, fin) or public.peut('promotions', 'voir'));
create policy promotions_creer on public.promotions for insert to authenticated with check (public.peut('promotions', 'creer'));
create policy promotions_modifier on public.promotions for update to authenticated using (public.peut('promotions', 'modifier')) with check (public.peut('promotions', 'modifier'));
create policy promotions_supprimer on public.promotions for delete to authenticated using (public.peut('promotions', 'supprimer'));

create policy codes_lire on public.codes_promo for select to authenticated using (public.peut('promotions', 'voir'));
create policy codes_creer on public.codes_promo for insert to authenticated with check (public.peut('promotions', 'creer'));
create policy codes_modifier on public.codes_promo for update to authenticated using (public.peut('promotions', 'modifier')) with check (public.peut('promotions', 'modifier'));
create policy codes_supprimer on public.codes_promo for delete to authenticated using (public.peut('promotions', 'supprimer'));

-- Contenus
create policy textes_lire on public.textes for select to anon, authenticated using (true);
create policy textes_creer on public.textes for insert to authenticated with check (public.peut('textes', 'modifier'));
create policy textes_modifier on public.textes for update to authenticated using (public.peut('textes', 'modifier')) with check (public.peut('textes', 'modifier'));

create policy parametres_lire on public.parametres for select to anon, authenticated
  using (cle not in ('email_equipe', 'modeles_emails') or public.est_equipe());
create policy parametres_creer on public.parametres for insert to authenticated
  with check (public.peut('parametres', 'modifier') or (cle in ('accueil', 'seo') and public.peut('pages', 'modifier')));
create policy parametres_modifier on public.parametres for update to authenticated
  using (public.peut('parametres', 'modifier') or (cle in ('accueil', 'seo') and public.peut('pages', 'modifier')))
  with check (public.peut('parametres', 'modifier') or (cle in ('accueil', 'seo') and public.peut('pages', 'modifier')));

create policy pages_lire on public.pages for select to anon, authenticated using (publie or public.peut('pages', 'voir'));
create policy pages_creer on public.pages for insert to authenticated with check (public.peut('pages', 'creer'));
create policy pages_modifier on public.pages for update to authenticated using (public.peut('pages', 'modifier')) with check (public.peut('pages', 'modifier'));
create policy pages_supprimer on public.pages for delete to authenticated using (public.peut('pages', 'supprimer') and type = 'libre');

-- Devis
create policy devis_lire on public.devis for select to authenticated
  using (client = auth.uid() or public.peut('devis', 'voir') or public.peut('statistiques', 'voir') or public.peut('production', 'voir'));
create policy devis_creer on public.devis for insert to authenticated
  with check (public.peut('devis', 'creer') or (client = auth.uid() and public.mon_role() is not null));
create policy devis_modifier on public.devis for update to authenticated
  using (public.peut('devis', 'modifier')) with check (public.peut('devis', 'modifier'));
create policy devis_annuler_client on public.devis for update to authenticated
  using (client = auth.uid() and statut = 'demande') with check (client = auth.uid() and statut in ('demande', 'annulee'));
create policy devis_supprimer on public.devis for delete to authenticated using (public.peut('devis', 'supprimer'));

create policy lignes_lire on public.devis_lignes for select to authenticated
  using (exists (select 1 from public.devis d where d.id = devis
                  and (d.client = auth.uid() or public.peut('devis', 'voir') or public.peut('statistiques', 'voir') or public.peut('production', 'voir'))));
create policy lignes_creer on public.devis_lignes for insert to authenticated
  with check (public.peut('devis', 'modifier')
              or exists (select 1 from public.devis d where d.id = devis and d.client = auth.uid() and d.statut = 'demande'));
create policy lignes_modifier on public.devis_lignes for update to authenticated
  using (public.peut('devis', 'modifier') or public.peut('production', 'modifier'))
  with check (public.peut('devis', 'modifier') or public.peut('production', 'modifier'));
create policy lignes_supprimer on public.devis_lignes for delete to authenticated using (public.peut('devis', 'modifier'));

create policy bats_lire on public.bats for select to authenticated
  using (public.peut('devis', 'voir') or public.peut('production', 'voir')
         or exists (select 1 from public.devis d where d.id = devis and d.client = auth.uid()));
create policy bats_creer on public.bats for insert to authenticated with check (public.peut('devis', 'modifier'));
create policy bats_modifier on public.bats for update to authenticated using (public.peut('devis', 'modifier')) with check (public.peut('devis', 'modifier'));

create policy paiements_lire on public.paiements for select to authenticated
  using (public.peut('paiements', 'voir') or public.peut('statistiques', 'voir')
         or exists (select 1 from public.devis d where d.id = devis and d.client = auth.uid()));
create policy paiements_creer on public.paiements for insert to authenticated with check (public.peut('paiements', 'creer'));
create policy paiements_modifier on public.paiements for update to authenticated using (public.peut('paiements', 'modifier')) with check (public.peut('paiements', 'modifier'));
create policy paiements_supprimer on public.paiements for delete to authenticated using (public.peut('paiements', 'supprimer'));

create policy emails_lire on public.emails for select to authenticated using (public.peut('emails', 'voir'));
create policy emails_modifier on public.emails for update to authenticated using (public.peut('emails', 'modifier')) with check (public.peut('emails', 'modifier'));

create policy journal_lire on public.journal for select to authenticated using (public.peut('journal', 'voir'));

-- Droits SQL minimaux en plus du RLS.
revoke all on public.journal, public.emails from anon;
revoke insert, update, delete on public.journal from authenticated;
revoke insert, delete on public.emails from authenticated;
revoke insert, update, delete on public.roles, public.textes, public.parametres, public.pages, public.categories, public.techniques,
  public.produits, public.promotions, public.codes_promo from anon;
grant select on public.suivi_devis to authenticated;
revoke execute on function public.notifier(text, bigint, jsonb), public.recalculer_devis(bigint) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Stockage : photos produits et médiathèque (publics), BAT (privés)
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public) values ('produits', 'produits', true) on conflict (id) do update set public = true;
insert into storage.buckets (id, name, public) values ('medias', 'medias', true) on conflict (id) do update set public = true;
insert into storage.buckets (id, name, public) values ('bat', 'bat', false) on conflict (id) do update set public = false;

do $$
declare n text;
begin
  foreach n in array array['produits_photos_lire', 'produits_photos_ecrire', 'produits_photos_modifier', 'produits_photos_supprimer',
                           'lz_public_lire', 'lz_produits_ecrire', 'lz_medias_ecrire', 'lz_images_supprimer', 'lz_bat_lire', 'lz_bat_ecrire'] loop
    execute format('drop policy if exists %I on storage.objects', n);
  end loop;
end $$;

create policy lz_public_lire on storage.objects for select to anon, authenticated using (bucket_id in ('produits', 'medias'));
create policy lz_produits_ecrire on storage.objects for insert to authenticated
  with check (bucket_id = 'produits' and (public.peut('produits', 'modifier') or public.peut('produits', 'creer') or public.peut('medias', 'creer')));
create policy lz_medias_ecrire on storage.objects for insert to authenticated
  with check (bucket_id = 'medias' and public.peut('medias', 'creer'));
create policy lz_images_supprimer on storage.objects for delete to authenticated
  using (bucket_id in ('produits', 'medias') and public.peut('medias', 'supprimer'));
create policy lz_bat_lire on storage.objects for select to authenticated
  using (bucket_id = 'bat' and (public.peut('devis', 'voir') or public.peut('production', 'voir')
         or exists (select 1 from public.devis d where d.id::text = split_part(name, '/', 1) and d.client = auth.uid())));
create policy lz_bat_ecrire on storage.objects for insert to authenticated
  with check (bucket_id = 'bat' and public.peut('devis', 'modifier'));
