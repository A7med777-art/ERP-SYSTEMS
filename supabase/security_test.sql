-- =====================================================================
--  Attack test: runs every attack as an anonymous website visitor
--  (exactly what anyone holding the public key can do).
--  Paste into Supabase → SQL Editor → Run. Nothing is saved: it ends with ROLLBACK,
--  so no rows stay behind and no notifications are sent.
--  Every row should show outcome = expected.
-- =====================================================================
begin;
create temp table sec_results(n serial, attack text, expected text, outcome text);
grant all on sec_results to anon; grant usage on sequence sec_results_n_seq to anon;

create function pg_temp.try_as_anon(attack text, expected text, stmt text, headers text default '{}')
returns void language plpgsql as $f$
declare r text;
begin
  begin
    perform set_config('request.headers', headers, true);
    execute 'set local role anon';
    execute stmt;
    r := 'SUCCEEDED';
  exception when others then
    r := 'BLOCKED (' || sqlstate || ': ' || left(sqlerrm, 60) || ')';
  end;
  execute 'reset role';
  insert into sec_results(attack, expected, outcome) values (attack, expected, r);
end $f$;

select pg_temp.try_as_anon('Read every client request', 'BLOCKED', 'select * from public.erp_signups limit 1');
select pg_temp.try_as_anon('Change a request', 'BLOCKED', 'update public.erp_signups set notes = ''hacked''');
select pg_temp.try_as_anon('Delete all requests', 'BLOCKED', 'delete from public.erp_signups');
select pg_temp.try_as_anon('Empty the table (truncate)', 'BLOCKED', 'truncate public.erp_signups');
select pg_temp.try_as_anon('Drop the table', 'BLOCKED', 'drop table public.erp_signups');
select pg_temp.try_as_anon('Read the attempts log', 'BLOCKED', 'select * from private.signup_attempts');
select pg_temp.try_as_anon('Read notification keys (Vault)', 'BLOCKED', 'select * from vault.decrypted_secrets');
select pg_temp.try_as_anon('Call the alert sender directly', 'BLOCKED', 'select private.lead_secret(''lead_ntfy_topic'')');
select pg_temp.try_as_anon('Huge text (3000 chars) to fill the DB', 'BLOCKED', 'insert into public.erp_signups(modules,industry,company_name,contact_name,email,notes) values (array[''sales''],''Retail'',''X'',''Y'',''big@example.com'',repeat(''a'',3000))', '{"x-forwarded-for":"10.0.0.1"}');
select pg_temp.try_as_anon('Fake email address', 'BLOCKED', 'insert into public.erp_signups(modules,industry,company_name,contact_name,email) values (array[''sales''],''Retail'',''X'',''Y'',''not-an-email'')', '{"x-forwarded-for":"10.0.0.2"}');
select pg_temp.try_as_anon('No modules', 'BLOCKED', 'insert into public.erp_signups(modules,industry,company_name,contact_name,email) values (array[]::text[],''Retail'',''X'',''Y'',''m@example.com'')', '{"x-forwarded-for":"10.0.0.3"}');
select pg_temp.try_as_anon('Invalid plan', 'BLOCKED', 'insert into public.erp_signups(modules,industry,company_name,contact_name,email,plan) values (array[''sales''],''Retail'',''X'',''Y'',''p@example.com'',''free-forever'')', '{"x-forwarded-for":"10.0.0.4"}');
select pg_temp.try_as_anon('Normal request', 'SUCCEEDED', 'insert into public.erp_signups(id,modules,industry,company_name,contact_name,email,status,created_at) values (''11111111-1111-1111-1111-111111111111'',array[''sales''],''Retail'',''Sec Test'',''Tester'',''  Forge@Example.com '',''active'',''2000-01-01'')', '{"x-forwarded-for":"10.0.0.5"}');

select pg_temp.try_as_anon('Same network, request ' || g, case when g <= 10 then 'SUCCEEDED' else 'BLOCKED' end,
  format('insert into public.erp_signups(modules,industry,company_name,contact_name,email) values (array[''sales''],''Retail'',''Flood'',''Bot'',''bot%s@example.com'')', g),
  '{"x-forwarded-for":"203.0.113.7"}') from generate_series(1,11) g;
select pg_temp.try_as_anon('Same email, request ' || g, case when g <= 3 then 'SUCCEEDED' else 'BLOCKED' end,
  'insert into public.erp_signups(modules,industry,company_name,contact_name,email) values (array[''sales''],''Retail'',''Spam'',''Bot'',''same@example.com'')',
  format('{"x-forwarded-for":"198.51.100.%s"}', g)) from generate_series(1,4) g;

insert into sec_results(attack, expected, outcome)
select 'Forged status/date were overwritten by server', 'new + true + forge@example.com',
       status || ' + ' || (created_at::date = current_date)::text || ' + ' || email
from public.erp_signups where id = '11111111-1111-1111-1111-111111111111';

insert into sec_results(attack, expected, outcome)
select 'Anon can run ERP function ' || p.oid::regprocedure, 'false', has_function_privilege('anon', p.oid, 'execute')::text
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prosecdef;

insert into sec_results(attack, expected, outcome)
select 'Anon access to ERP table ' || c.relname, 'no access',
       case when has_table_privilege('anon', c.oid, 'select') then 'has SELECT grant (RLS on: ' || c.relrowsecurity || ')' else 'no access' end
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' and c.relname <> 'erp_signups';

select n, attack, expected, outcome,
       case when outcome like expected || '%' then 'PASS' else 'FAIL' end as result
from sec_results order by n;
rollback;
