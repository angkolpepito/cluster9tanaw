-- CLUSTER 9 TANAW • run in the CLUSTER Supabase project (SQL Editor). Safe to run again: every statement is repeatable.
create extension if not exists pgcrypto with schema extensions;

create table if not exists schools (
  id uuid primary key default gen_random_uuid(),
  school_code text unique,
  name text not null,
  depts text[] not null default '{Elementary}',   -- any of: Elementary, JHS, SHS
  push_hash text,
  last_push timestamptz,
  created_at timestamptz default now()
);
create table if not exists profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('psds','school_head')),
  school_id uuid references schools(id) on delete cascade,
  full_name text
);
-- One generic table holds every encoded indicator (module/row/column grid)
create table if not exists cluster_data (
  school_id uuid references schools(id) on delete cascade,
  sy text not null, module text not null, row_key text not null, col_key text not null,
  value numeric, updated_at timestamptz default now(),
  primary key (school_id, sy, module, row_key, col_key)
);
-- Pushed from Project COMPASS
create table if not exists compass_gsa (
  school_id uuid references schools(id) on delete cascade, sy text, subject text, grade text, term text, value numeric,
  primary key (school_id, sy, subject, grade, term));
create table if not exists compass_mps (
  school_id uuid references schools(id) on delete cascade, sy text, subject text, grade text, term text,
  st1 numeric, st2 numeric, exam numeric,
  primary key (school_id, sy, subject, grade, term));

create or replace function is_psds() returns boolean language sql security definer stable as
$$ select exists(select 1 from profiles where user_id = auth.uid() and role = 'psds') $$;
create or replace function my_school() returns uuid language sql security definer stable as
$$ select school_id from profiles where user_id = auth.uid() $$;

alter table schools enable row level security;
alter table profiles enable row level security;
alter table cluster_data enable row level security;
alter table compass_gsa enable row level security;
alter table compass_mps enable row level security;

drop policy if exists schools_read on schools;
create policy schools_read on schools for select using (is_psds() or id = my_school());
drop policy if exists schools_psds on schools;
create policy schools_psds on schools for all using (is_psds()) with check (is_psds());
drop policy if exists profiles_read on profiles;
create policy profiles_read on profiles for select using (user_id = auth.uid() or is_psds());
drop policy if exists data_read on cluster_data;
create policy data_read on cluster_data for select using (is_psds() or school_id = my_school());
-- Encoding: school head only, own school only
drop policy if exists data_write on cluster_data;
create policy data_write on cluster_data for all
  using (school_id = my_school() and not is_psds()) with check (school_id = my_school() and not is_psds());
drop policy if exists gsa_read on compass_gsa;
create policy gsa_read on compass_gsa for select using (is_psds() or school_id = my_school());
drop policy if exists mps_read on compass_mps;
create policy mps_read on compass_mps for select using (is_psds() or school_id = my_school());

-- PSDS generates a push token per school (shown once; only its hash is stored)
create or replace function new_push_token(p_school uuid) returns text language plpgsql security definer
set search_path = public, extensions as $$
declare t text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
begin
  if not is_psds() then raise exception 'PSDS only'; end if;
  update schools set push_hash = encode(digest(t, 'sha256'), 'hex') where id = p_school;
  return t;
end $$;

-- Called by the patched Project COMPASS (admin dashboard) to push its data
create or replace function push_compass(p_code text, p_token text, p_sy text, p_gsa jsonb, p_mps jsonb)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare s schools;
begin
  select * into s from schools where school_code = p_code;
  if s.id is null or s.push_hash is null or s.push_hash <> encode(digest(p_token, 'sha256'), 'hex') then
    raise exception 'Invalid school code or push token'; end if;
  delete from compass_gsa where school_id = s.id and sy = p_sy;
  delete from compass_mps where school_id = s.id and sy = p_sy;
  insert into compass_gsa select s.id, p_sy, r.subject, r.grade, r.term, r.value
    from jsonb_to_recordset(p_gsa) as r(subject text, grade text, term text, value numeric);
  insert into compass_mps select s.id, p_sy, r.subject, r.grade, r.term, r.st1, r.st2, r.exam
    from jsonb_to_recordset(p_mps) as r(subject text, grade text, term text, st1 numeric, st2 numeric, exam numeric);
  update schools set last_push = now() where id = s.id;
  return 'ok';
end $$;
grant execute on function push_compass(text, text, text, jsonb, jsonb) to anon, authenticated;
grant execute on function new_push_token(uuid) to authenticated;

-- AFTER creating the PSDS user in Authentication → Users (email: psds@cluster9.tanaw.local), run:
-- insert into profiles (user_id, role, full_name) select id, 'psds', 'PSDS, Cluster 9' from auth.users where email = 'psds@cluster9.tanaw.local';


-- CLUSTER 9 TANAW • Project HANDA: top learners in the Cluster Mock Test
-- Run once in the cluster Supabase project (SQL Editor). Safe to run again.
create table if not exists handa_learners (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  sy text not null,
  grade text not null check (grade in ('10','12')),
  learner_name text not null,
  score numeric,
  created_at timestamptz default now()
);
create index if not exists handa_learners_rank on handa_learners (sy, grade, score desc);
alter table handa_learners enable row level security;
drop policy if exists handa_read on handa_learners;
drop policy if exists handa_write on handa_learners;
-- PSDS sees every school; a school head sees and edits only their own school's list
create policy handa_read on handa_learners for select using (is_psds() or school_id = my_school());
create policy handa_write on handa_learners for all
  using (school_id = my_school() and not is_psds())
  with check (school_id = my_school() and not is_psds());


-- CLUSTER 9 TANAW • Personnel roster (birthdate, employment status, appointment and promotion dates)
-- Run once in the cluster Supabase project (SQL Editor). Safe to run again.
-- Birthdates are personal data: access is limited to the PSDS office and the school's own head.
create table if not exists personnel_roster (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  full_name text not null,
  position text,
  status text,
  birthdate date,
  date_appointed date,
  date_promoted date,
  remarks text,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  check (date_promoted is null or date_appointed is null or date_promoted >= date_appointed)
);
create index if not exists personnel_roster_school on personnel_roster (school_id);
alter table personnel_roster enable row level security;
drop policy if exists roster_read on personnel_roster;
drop policy if exists roster_write on personnel_roster;
create policy roster_read on personnel_roster for select using (is_psds() or school_id = my_school());
create policy roster_write on personnel_roster for all
  using (school_id = my_school() and not is_psds())
  with check (school_id = my_school() and not is_psds());


-- CLUSTER 9 TANAW • Batch 4: innovations, SLAC (LAC plan + sessions) and the LAC plan file storage
-- Run once in the cluster Supabase project (SQL Editor). Safe to run again.
-- SGC, PTA, ownership, metal detectors, technical assistance and ALS use the existing cluster_data table: nothing to add.

-- 1) Innovations and best practices (a list per school)
create table if not exists school_innovations (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  title text not null,
  proponents text,
  designation text,
  category text,
  sy_started text,
  description text,
  results text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists school_innovations_school on school_innovations (school_id);
-- for projects that already ran this file before proponents were added:
alter table school_innovations add column if not exists proponents text;
alter table school_innovations add column if not exists designation text;

-- 2) SLAC: LAC plan approval and uploaded file (one row per school per school year)
create table if not exists lac_plans (
  school_id uuid not null references schools(id) on delete cascade,
  sy text not null,
  approved boolean not null default false,
  file_path text,
  file_name text,
  updated_at timestamptz default now(),
  primary key (school_id, sy)
);

-- 3) SLAC: LAC sessions implemented
create table if not exists lac_sessions (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id) on delete cascade,
  sy text not null,
  title text not null,
  participants int check (participants is null or participants >= 0),
  date_implemented date,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists lac_sessions_school_sy on lac_sessions (school_id, sy);

-- Row-level security: PSDS reads everything; a school head reads and edits only their own school
alter table school_innovations enable row level security;
alter table lac_plans enable row level security;
alter table lac_sessions enable row level security;
drop policy if exists inn_read on school_innovations;  drop policy if exists inn_write on school_innovations;
drop policy if exists lacp_read on lac_plans;          drop policy if exists lacp_write on lac_plans;
drop policy if exists lacs_read on lac_sessions;       drop policy if exists lacs_write on lac_sessions;
create policy inn_read  on school_innovations for select using (is_psds() or school_id = my_school());
create policy inn_write on school_innovations for all using (school_id = my_school() and not is_psds()) with check (school_id = my_school() and not is_psds());
create policy lacp_read  on lac_plans for select using (is_psds() or school_id = my_school());
create policy lacp_write on lac_plans for all using (school_id = my_school() and not is_psds()) with check (school_id = my_school() and not is_psds());
create policy lacs_read  on lac_sessions for select using (is_psds() or school_id = my_school());
create policy lacs_write on lac_sessions for all using (school_id = my_school() and not is_psds()) with check (school_id = my_school() and not is_psds());

-- 4) Private storage bucket for the approved LAC plan files (10 MB limit).
-- Files are stored under <school_id>/<school year>/..., so each school head can only touch their own folder.
insert into storage.buckets (id, name, public, file_size_limit)
values ('lac-plans', 'lac-plans', false, 10485760)
on conflict (id) do update set file_size_limit = excluded.file_size_limit, public = false;
drop policy if exists lac_files_read on storage.objects;
drop policy if exists lac_files_insert on storage.objects;
drop policy if exists lac_files_delete on storage.objects;
create policy lac_files_read on storage.objects for select
  using (bucket_id = 'lac-plans' and (is_psds() or (storage.foldername(name))[1] = my_school()::text));
create policy lac_files_insert on storage.objects for insert
  with check (bucket_id = 'lac-plans' and not is_psds() and (storage.foldername(name))[1] = my_school()::text);
create policy lac_files_delete on storage.objects for delete
  using (bucket_id = 'lac-plans' and not is_psds() and (storage.foldername(name))[1] = my_school()::text);


-- CLUSTER 9 TANAW • Project HANDA: editable Mock NAT subject list
-- Run once in the cluster Supabase project (SQL Editor). Safe to run again.
-- The PSDS edits the subjects (per grade level) in Project HANDA > "Edit the Mock NAT subject list".
-- Until a list is saved, the app uses its default five subjects.
create table if not exists handa_subjects (
  grade text not null check (grade in ('10','12')),
  subject text not null check (length(trim(subject)) > 0 and position('|' in subject) = 0),
  sort int not null default 0,
  primary key (grade, subject)
);
alter table handa_subjects enable row level security;
drop policy if exists handa_subjects_read on handa_subjects;
create policy handa_subjects_read on handa_subjects for select using (auth.uid() is not null);
-- No direct write policy: the list is saved only through handa_save_subjects() below (PSDS only).

-- Saves one grade level's list in a single transaction. Each item is {"old": previous name or "", "name": new name}.
-- Renamed subjects keep their encoded scores (cluster_data row keys are moved to the new name).
create or replace function handa_save_subjects(p_grade text, p_items jsonb) returns text
language plpgsql security definer set search_path = public as $$
declare it record;
begin
  if not is_psds() then raise exception 'PSDS only'; end if;
  if p_grade not in ('10','12') then raise exception 'Grade must be 10 or 12'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Keep at least one subject'; end if;
  -- phase 1: park renamed rows under temporary keys (so swaps and chains of renames cannot collide)
  for it in
    select e->>'old' as old_name, trim(e->>'name') as new_name, ord
    from jsonb_array_elements(p_items) with ordinality as t(e, ord)
    where coalesce(e->>'old','') <> '' and (e->>'old') <> trim(e->>'name')
  loop
    update cluster_data set row_key = p_grade || '|~' || it.ord
      where module = 'handa' and row_key = p_grade || '|' || it.old_name;
  end loop;
  -- phase 2: move them to their new names (stale scores under a reused name are replaced)
  for it in
    select trim(e->>'name') as new_name, ord
    from jsonb_array_elements(p_items) with ordinality as t(e, ord)
    where coalesce(e->>'old','') <> '' and (e->>'old') <> trim(e->>'name')
  loop
    delete from cluster_data where module = 'handa' and row_key = p_grade || '|' || it.new_name;
    update cluster_data set row_key = p_grade || '|' || it.new_name
      where module = 'handa' and row_key = p_grade || '|~' || it.ord;
  end loop;
  delete from handa_subjects where grade = p_grade;
  insert into handa_subjects (grade, subject, sort)
    select p_grade, trim(e->>'name'), ord from jsonb_array_elements(p_items) with ordinality as t(e, ord);
  return 'ok';
end $$;
grant execute on function handa_save_subjects(text, jsonb) to authenticated;


-- CLUSTER 9 TANAW • SNED learners: editable category list
-- Run once in the cluster Supabase project (SQL Editor). Safe to run again.
-- The PSDS edits the categories in Schools & logins > "SNED categories".
-- Counts per grade level and gender are stored in the existing cluster_data table (module 'sned',
-- row = grade|M or grade|F, column = category id), so nothing else is needed.
-- Until a list is saved, the app uses its default 13 categories.
create table if not exists sned_categories (
  id text primary key check (id ~ '^[a-z0-9_]+$'),
  name text not null check (length(trim(name)) > 0),
  sort int not null default 0
);
alter table sned_categories enable row level security;
drop policy if exists sned_cat_read on sned_categories;
drop policy if exists sned_cat_write on sned_categories;
create policy sned_cat_read on sned_categories for select using (auth.uid() is not null);
create policy sned_cat_write on sned_categories for all using (is_psds()) with check (is_psds());


-- CLUSTER 9 TANAW • Encoder accounts: several logins per school, each limited to assigned tabs
-- Run once in the cluster Supabase project (SQL Editor). Safe to run again.
-- Roles: psds (cluster office), school_head (all tabs of their school), encoder (only the tabs assigned to them).
-- The restriction is enforced here, in row-level security: an encoder can neither read nor save data of a tab
-- that was not assigned to them, whatever the page shows.

-- 1) profiles: encoder role, assigned tabs, username
alter table profiles add column if not exists tabs text[] not null default '{}';
alter table profiles add column if not exists username text;
alter table profiles drop constraint if exists profiles_role_check;
alter table profiles add constraint profiles_role_check check (role in ('psds','school_head','encoder'));

-- 2) which stored data each dashboard tab (section) covers.
--    module = a cluster_data module, or '@name' for a separate table. can_edit=false means read-only for that tab.
create table if not exists tab_modules (
  section text not null, module text not null, can_edit boolean not null default true,
  primary key (section, module)
);
alter table tab_modules enable row level security;
drop policy if exists tab_modules_read on tab_modules;
create policy tab_modules_read on tab_modules for select using (auth.uid() is not null);
insert into tab_modules (section, module, can_edit) values
  ('learners','learners',true),
  ('personnel','personnel',true), ('personnel','@roster',true),
  ('positions','positions',true),
  ('pmes','pmes',true),
  ('rates','rates',true),
  ('academic','@academic',false),
  ('handa','handa',true), ('handa','@handa_top',true),
  ('mooe','mooe',true),
  ('okdeped','bmi',true), ('okdeped','gulayan',true), ('okdeped','canteen',true), ('okdeped','rh',true), ('okdeped','zsup',true),
  ('philiri','philiri',true),
  ('aral','aral',true), ('aral','aral2',true),
  ('ops','ops',true), ('ops','sgc',true), ('ops','pta',true), ('ops','own',true),
  ('innov','@innov',true),
  ('ta','ta',true),
  ('als','als',true),
  ('sned','sned',true), ('sned','learners',false),
  ('slac','@slac',true)
on conflict (section, module) do update set can_edit = excluded.can_edit;

-- 3) helper functions
create or replace function my_role() returns text language sql security definer stable set search_path = public as
$$ select role from profiles where user_id = auth.uid() $$;
-- school head: everything of their school; encoder: only modules of their assigned tabs
create or replace function can_read(p_module text) returns boolean language sql security definer stable set search_path = public as
$$ select exists(select 1 from profiles p where p.user_id = auth.uid() and (p.role = 'school_head' or
     (p.role = 'encoder' and exists(select 1 from tab_modules t where t.module = p_module and t.section = any(p.tabs))))) $$;
create or replace function can_edit(p_module text) returns boolean language sql security definer stable set search_path = public as
$$ select exists(select 1 from profiles p where p.user_id = auth.uid() and (p.role = 'school_head' or
     (p.role = 'encoder' and exists(select 1 from tab_modules t where t.module = p_module and t.can_edit and t.section = any(p.tabs))))) $$;

-- 4) profiles: a school head can list the encoders of their own school
drop policy if exists profiles_read on profiles;
create policy profiles_read on profiles for select
  using (user_id = auth.uid() or is_psds() or (role = 'encoder' and school_id = my_school() and my_role() = 'school_head'));

-- 5) data policies (PSDS still reads everything and edits nothing)
drop policy if exists data_read on cluster_data;
create policy data_read on cluster_data for select using (is_psds() or (school_id = my_school() and can_read(module)));
drop policy if exists data_write on cluster_data;
create policy data_write on cluster_data for all
  using (school_id = my_school() and not is_psds() and can_edit(module))
  with check (school_id = my_school() and not is_psds() and can_edit(module));
drop policy if exists gsa_read on compass_gsa;
create policy gsa_read on compass_gsa for select using (is_psds() or (school_id = my_school() and can_read('@academic')));
drop policy if exists mps_read on compass_mps;
create policy mps_read on compass_mps for select using (is_psds() or (school_id = my_school() and can_read('@academic')));

drop policy if exists handa_read on handa_learners;
drop policy if exists handa_write on handa_learners;
create policy handa_read on handa_learners for select using (is_psds() or (school_id = my_school() and can_read('@handa_top')));
create policy handa_write on handa_learners for all
  using (school_id = my_school() and not is_psds() and can_edit('@handa_top'))
  with check (school_id = my_school() and not is_psds() and can_edit('@handa_top'));

drop policy if exists roster_read on personnel_roster;
drop policy if exists roster_write on personnel_roster;
create policy roster_read on personnel_roster for select using (is_psds() or (school_id = my_school() and can_read('@roster')));
create policy roster_write on personnel_roster for all
  using (school_id = my_school() and not is_psds() and can_edit('@roster'))
  with check (school_id = my_school() and not is_psds() and can_edit('@roster'));

drop policy if exists inn_read on school_innovations;
drop policy if exists inn_write on school_innovations;
create policy inn_read on school_innovations for select using (is_psds() or (school_id = my_school() and can_read('@innov')));
create policy inn_write on school_innovations for all
  using (school_id = my_school() and not is_psds() and can_edit('@innov'))
  with check (school_id = my_school() and not is_psds() and can_edit('@innov'));

drop policy if exists lacp_read on lac_plans;   drop policy if exists lacp_write on lac_plans;
drop policy if exists lacs_read on lac_sessions; drop policy if exists lacs_write on lac_sessions;
create policy lacp_read on lac_plans for select using (is_psds() or (school_id = my_school() and can_read('@slac')));
create policy lacp_write on lac_plans for all
  using (school_id = my_school() and not is_psds() and can_edit('@slac'))
  with check (school_id = my_school() and not is_psds() and can_edit('@slac'));
create policy lacs_read on lac_sessions for select using (is_psds() or (school_id = my_school() and can_read('@slac')));
create policy lacs_write on lac_sessions for all
  using (school_id = my_school() and not is_psds() and can_edit('@slac'))
  with check (school_id = my_school() and not is_psds() and can_edit('@slac'));

drop policy if exists lac_files_read on storage.objects;
drop policy if exists lac_files_insert on storage.objects;
drop policy if exists lac_files_delete on storage.objects;
create policy lac_files_read on storage.objects for select
  using (bucket_id = 'lac-plans' and (is_psds() or ((storage.foldername(name))[1] = my_school()::text and can_read('@slac'))));
create policy lac_files_insert on storage.objects for insert
  with check (bucket_id = 'lac-plans' and not is_psds() and (storage.foldername(name))[1] = my_school()::text and can_edit('@slac'));
create policy lac_files_delete on storage.objects for delete
  using (bucket_id = 'lac-plans' and not is_psds() and (storage.foldername(name))[1] = my_school()::text and can_edit('@slac'));
