-- Use this if the in-app "Login" button is unavailable (e.g. Netlify Drop without functions).
-- 1) Supabase → Authentication → Users → Add user → Create new user
--    Email: <username>@cluster9.tanaw.local   Password: (temporary)   tick "Auto Confirm User"
-- 2) Link that login to its school (change the email and the school ID):
insert into profiles (user_id, role, school_id)
select u.id, 'school_head', s.id
from auth.users u, schools s
where u.email = 'username@cluster9.tanaw.local' and s.school_code = '300001';
