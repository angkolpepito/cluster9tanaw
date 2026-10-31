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
