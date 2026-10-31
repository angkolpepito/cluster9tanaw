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
