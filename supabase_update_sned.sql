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
