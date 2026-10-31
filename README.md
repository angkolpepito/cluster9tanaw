# Cluster 9 TANAW (Tracking and Analysis of Needed Academic and Workforce Data)
One click. Clear insights. Better guiding decisions toward Security, Harmony, and Excellence.

Tanaw = "vantage point". Netlify (static site + 1 function) + Supabase (database, auth, row-level security).

## Files
- index.html — login, school-head encoder, PSDS dashboard, schools & logins admin
- config.js — your cluster Supabase URL + anon key
- supabase_setup.sql — tables, security rules, COMPASS push function
- netlify.toml, netlify/functions/account.mjs — deploy settings and login creator
- Project_COMPASS_v3_cluster.html — your COMPASS with the Cluster 9 push button added (snippet also in compass-push-snippet.js)

## Deploy (about 20 minutes)
1. Supabase: create a NEW project for the cluster (separate from COMPASS). SQL Editor → paste supabase_setup.sql → Run.
2. Supabase → Authentication → Users → Add user: email psds@cluster9.tanaw.local, a strong password, tick auto-confirm.
   Then run the last (commented) INSERT line in supabase_setup.sql to make it the PSDS account. Sign-in username is "psds".
3. Supabase → Project Settings → API: copy the URL and anon key into config.js.
4. Netlify → Add new site → deploy this folder (drag-and-drop or Git). Site settings → Environment variables:
   SUPABASE_URL = your project URL, SUPABASE_SERVICE_KEY = the service_role key (secret; never put it in config.js). Redeploy.
5. Sign in as psds → Schools & logins → Add school (name, DepEd school ID, departments).
   Click Login for each school to create the school head's username and temporary password.
6. Click COMPASS token (shown once). Open Project_COMPASS_v3_cluster.html, find the cluster-push block at the bottom,
   fill URL, ANON, CODE (the school ID), TOKEN, SY, then deploy that file as your COMPASS site.
   Admin sees a "Send data to Cluster 9" button; data also auto-sends 20 s after COMPASS reloads data.

## How data flows
- School head signs in -> Encode data (learners, personnel, rates, MOOE, BMI, Phil-IRI, ARAL, operations). Only own school, enforced by the database.
- COMPASS admin -> GSA and MPS pushed into compass_gsa / compass_mps -> appears under GSA & MPS.
- PSDS sees every school; the PSDS account cannot edit school data.

## Notes
- COMPASS has no school-year field; the SY in the snippet decides which year the push lands in. Change it each year.
- "MPS overall" = mean of ST1, ST2 and Exam, since COMPASS computes its own overall in the browser.
- Each school runs its own COMPASS (own Supabase) and pushes with its own token, so one leaked token only affects one school.

## Netlify Drop
Upload Project_TANAW_Netlify_Drop.zip (site files at the zip root). config.js already holds your Supabase URL and anon key.
If Drop does not build the login function, create logins in Supabase instead: see school-head-login.sql.
For the in-app Login button, deploy through Git or the Netlify CLI and set SUPABASE_URL and SUPABASE_SERVICE_KEY.

## What is new in this version
- Name and tagline on the home page, login page, header and footer: Cluster 9 TANAW.
- Learners & enrolment: previous vs current school year (cluster, per grade level, per school, % change). School heads encode both years in Encode data > Enrolment; it saves into the Learners records of each year, so no double entry.
- Position distribution (new tab + encoder): Teacher I-VII, Master Teacher I-V, Head Teacher I-VI, Principal I-IV, Administrative Assistant I-III, Administrative Officer I-V, Project Development Officer I-III and other non-teaching posts, by gender. Edit the POSG list near the top of the script in index.html to change positions.
- Teacher PMES (new tab + encoder): number of teachers per rating (Outstanding to Poor) for the last three school years before the selected school year.
- Performance indicators (enhanced from Completion & rates): added repetition rate; previous vs current comparison for completion, simple dropout, repetition, graduation and promotion.
- MOOE & GAD (enhanced): GAD allocation/attribution and quarterly GAD utilization, with GAD share of MOOE (5% reference line).
- No database change is needed: all new data uses the existing cluster_data table. Just redeploy.

## Batch 2 additions
- BMI and Phil-IRI are now separate tabs. "OK sa DepEd" holds BMI, Gulayan sa Paaralan, Canteen, Reproductive Health and Zero Single-Use Plastic (one encoder tab each).
- ARAL: new encoder "ARAL categories & progress" (Literacy/Numeracy x ARAL Basic/ARAL Plus: learners, improved, met target, pre-test and post-test mean) and matching charts and per-school tables. The old tutors/totals encoder is kept.
- Project HANDA: Mock NAT MPS and examinees per subject for Grades 10 and 12, previous and current school year side by side (edit the subjects in the HS list near the top of the script); school ranking with movement; per-subject matrix; top 10 learners per grade.
- REQUIRED for the top-10 learners (existing project): run supabase_update_handa.sql once; new projects get it automatically from supabase_setup.sql in the cluster Supabase SQL Editor. Everything else needs no database change. Until it is run, the rest of HANDA works and the top-10 area shows a notice.
- Privacy: school heads see only their own school's learner list; the cluster-wide top 10 shows on the PSDS dashboard.

## Batch 3: Personnel roster
- New encoder "Personnel roster": name, position, employment status (Permanent, Probationary, Temporary, Substitute, LSB appointee, Contract of Service, Job Order, Others), birthdate, date of original appointment, date of last promotion, remarks. Age, years in service (from original appointment) and years since last promotion are computed from today's date.
- The Personnel dashboard tab now also shows status, age, service and promotion-gap charts, a per-school summary and the full roster.
- REQUIRED (existing project): run supabase_update_personnel.sql once. New projects get it from supabase_setup.sql.
- Privacy: names and birthdates are visible only to the PSDS and the school's own head (row-level security).

## Batch 4
- Operations tab: SGC preparedness checklist, PTA participation (attendance, meetings, contributions; level is derived from attendance), school ownership and land area by document type (saved once, carried over every school year), metal detectors.
- New tabs: Innovations (best-practice catalogue with search), Technical assistance (Pakig-AMBIT, Project BISITA, regular PSDS monitoring, check boxes per school year from SY 2024-2025), ALS (Junior and Senior High School enrollees), SLAC (Division-approved LAC plan check box, plan file upload, LAC sessions with title, participants and date).
- REQUIRED (existing project): run supabase_update_batch4.sql once. It creates the innovations and SLAC tables and the private "lac-plans" storage bucket with per-school access rules. New projects get it from supabase_setup.sql.
- SGC, PTA, ownership, metal detectors, technical assistance and ALS need no database change.

## Batch 4b
- Innovations now record the proponent(s) and designation(s) (several proponents separated by semicolons, designations in the same order). Existing projects: re-run supabase_update_batch4.sql once (it adds the two columns safely).

## Batch 5: editable HANDA subjects and SNED learners
- Project HANDA: the PSDS dashboard has a new card, "Edit the Mock NAT subject list". For Grade 10 and Grade 12 separately you can rename, add, remove and reorder subjects, then press Save. The list drives the school-head encoder, charts, rankings and per-subject matrix. Renaming keeps the scores already encoded under the old name. Removing only hides a subject: its scores stay saved and return if the same name is added again. School heads see the list but cannot change it.
- REQUIRED (existing project): run supabase_update_handa_subjects.sql once. It creates the handa_subjects table and the PSDS-only handa_save_subjects() function. New projects get it from supabase_setup.sql. Until it is run, the default five subjects (English, Filipino, Mathematics, Science, Araling Panlipunan) are used.
- New tab "SNED learners" (dashboard) and "SNED learners" encoder: learners with disabilities per school, split by grade level (Kindergarten to Grade 12, following the school's departments) and gender, one column per category. The dashboard shows totals, share of enrolment, previous vs current school year, charts by school, grade level and category, and tables per school, per school and grade level, and per school and category. Counts only; no learner names.
- The SNED categories are editable by the PSDS in Schools & logins > "SNED categories" (rename, add, remove, reorder, reset to the 13 defaults). Categories have permanent ids, so renaming keeps the counts already encoded; removing only hides a category.
- REQUIRED (existing project): run supabase_update_sned.sql once. It creates the sned_categories table. New projects get it from supabase_setup.sql. Until it is run, the 13 default categories are used. Counts use the existing cluster_data table.
- Note: an earlier draft of the SNED encoder stored counts by category and gender only (no grade level). If you encoded anything in that draft, re-enter it by grade level.

## Batch 6: encoder accounts (several logins per school)
- Roles: PSDS (cluster office), school head (every tab of their school) and encoder (only the tabs assigned to them). A school can have up to 25 encoders, one per data owner.
- The school head (Encoder accounts tab) and the PSDS (Encoder accounts tab, pick the school) create encoders: full name, username, temporary password and the tabs the person owns. Edit tabs, reset the password or remove the login at any time. Personnel includes the roster with birthdates, so tick it only for the right person.
- An encoder sees only the assigned tabs: on Encode data and on the dashboard (no Overview, no other tabs), for their own school only. The Academic tab (GSA & MPS from COMPASS) is view-only. SNED also lets the encoder read the school's enrolment (for the percent of enrolment); the encoder cannot change it.
- The limits are enforced by the database (row-level security), not only by the page, so a modified page cannot read or save an unassigned tab.
- REQUIRED (existing project): run supabase_update_accounts.sql once, and run it LAST: it rewrites the access rules that earlier update files created, so re-run it if you ever re-run supabase_update_personnel.sql, supabase_update_handa.sql or supabase_update_batch4.sql. New projects get it at the end of supabase_setup.sql.
- REQUIRED for creating logins in the app: deploy through Git (not Netlify Drop) and set SUPABASE_URL and SUPABASE_SERVICE_KEY in Netlify > Site settings > Environment variables, then redeploy. netlify/functions/account.mjs now handles school head and encoder logins.
- Usernames are shared by the whole cluster (login is username@cluster9.tanaw.local), so use distinct ones such as the first initial plus surname; the app reports a taken username.
