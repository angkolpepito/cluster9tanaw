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
