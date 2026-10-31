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
