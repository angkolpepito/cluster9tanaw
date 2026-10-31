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
