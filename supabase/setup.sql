-- =====================================================================
--  ERP & CRM landing page — full database setup for Supabase
--  Paste the whole file into Supabase → SQL Editor → Run.
--  Safe to run more than once: it never drops the table or deletes rows.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1) Table: one row per client request from the website
-- ---------------------------------------------------------------------
create table if not exists public.erp_signups (
  id             uuid primary key default gen_random_uuid(),
  created_at     timestamptz not null default now(),
  status         text not null default 'new',
  plan           text not null default 'growth',
  modules        text[] not null,
  industry       text not null,
  company_name   text not null,
  contact_name   text not null,
  email          text not null,
  phone          text,
  country        text,
  company_size   text,
  current_system text,
  data_sources   text[] not null default '{}',
  record_volume  text,
  notes          text,
  locale         text,
  user_agent     text
);

-- Rules for what a valid request looks like (added only if missing).
do $$
declare c record;
begin
  for c in select * from (values
    ('erp_signups_status_check',        'status in (''new'',''contacted'',''onboarding'',''active'',''rejected'')'),
    ('erp_signups_plan_check',          'plan in (''starter'',''growth'',''enterprise'')'),
    ('erp_signups_modules_check',       'cardinality(modules) between 1 and 20'),
    ('erp_signups_industry_check',      'char_length(industry) between 1 and 80'),
    ('erp_signups_company_name_check',  'char_length(company_name) between 1 and 160'),
    ('erp_signups_contact_name_check',  'char_length(contact_name) between 1 and 120'),
    ('erp_signups_email_check',         'char_length(email) <= 254 and email ~* ''^[^@\s]+@[^@\s]+\.[^@\s]+$'''),
    ('erp_signups_phone_check',         'char_length(phone) <= 40'),
    ('erp_signups_country_check',       'char_length(country) <= 80'),
    ('erp_signups_company_size_check',  'company_size in (''1-10'',''11-50'',''51-200'',''201-1000'',''1000+'')'),
    ('erp_signups_current_system_check','char_length(current_system) <= 120'),
    ('erp_signups_data_sources_check',  'cardinality(data_sources) <= 12'),
    ('erp_signups_record_volume_check', 'record_volume in (''<10k'',''10k-100k'',''100k-1m'',''1m+'')'),
    ('erp_signups_notes_check',         'char_length(notes) <= 2000'),
    ('erp_signups_locale_check',        'char_length(locale) <= 20'),
    ('erp_signups_user_agent_check',    'char_length(user_agent) <= 400')
  ) as t(name, expr)
  loop
    if not exists (select 1 from pg_constraint where conname = c.name and conrelid = 'public.erp_signups'::regclass) then
      execute format('alter table public.erp_signups add constraint %I check (%s)', c.name, c.expr);
    end if;
  end loop;
end $$;

create index if not exists erp_signups_created_at_idx on public.erp_signups (created_at desc);
create index if not exists erp_signups_status_idx     on public.erp_signups (status);


-- ---------------------------------------------------------------------
-- 2) Security: the website may only ADD new requests.
--    Nobody can read, edit or delete them through the public API key.
--    You read them in the Supabase dashboard (Table Editor).
-- ---------------------------------------------------------------------
alter table public.erp_signups enable row level security;

revoke all on table public.erp_signups from anon, authenticated;
grant insert on table public.erp_signups to anon, authenticated;

drop policy if exists "Anyone can submit a signup" on public.erp_signups;
create policy "Anyone can submit a signup" on public.erp_signups
  for insert to anon, authenticated
  with check (status = 'new');


-- ---------------------------------------------------------------------
-- 3) Instant notifications for every new request
--    Phone push (ntfy, free, no account) works as soon as the topic is set.
--    WhatsApp (CallMeBot) and email (Resend) switch on when you add their keys.
--    Keys live in Supabase Vault, never in the website code.
-- ---------------------------------------------------------------------
create extension if not exists pg_net with schema extensions;
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create or replace function private.lead_secret(secret_name text)
returns text language sql stable security definer set search_path = '' as $$
  select decrypted_secret from vault.decrypted_secrets where name = secret_name limit 1
$$;

create or replace function private.send_lead_alert(r public.erp_signups)
returns void language plpgsql security definer set search_path = '' as $$
declare
  topic   text := private.lead_secret('lead_ntfy_topic');
  wa_to   text := private.lead_secret('lead_whatsapp_phone');
  wa_key  text := private.lead_secret('lead_callmebot_apikey');
  rs_key  text := private.lead_secret('lead_resend_api_key');
  mail_to text := private.lead_secret('lead_notify_email');
  title   text := 'New ERP request: ' || r.company_name;
  body    text := concat_ws(E'\n',
                    'Name: '     || r.contact_name,
                    'Company: '  || r.company_name,
                    'Phone: '    || coalesce(r.phone, '-'),
                    'Email: '    || r.email,
                    'Industry: ' || r.industry,
                    'Modules: '  || array_to_string(r.modules, ', '),
                    'Plan: '     || r.plan,
                    'Size: '     || coalesce(r.company_size, '-'),
                    'Country: '  || coalesce(r.country, '-'),
                    'Notes: '    || coalesce(r.notes, '-'));
  dashboard text := 'https://supabase.com/dashboard/project/vtzzqhbtnqudhtxnbykm/editor';
begin
  if topic is not null then
    perform net.http_post(
      url     := 'https://ntfy.sh/',
      body    := jsonb_build_object('topic', topic, 'title', title, 'message', body,
                                    'tags', jsonb_build_array('briefcase'), 'priority', 4, 'click', dashboard),
      headers := '{"Content-Type":"application/json"}'::jsonb);
  end if;

  if wa_to is not null and wa_key is not null then
    perform net.http_get(
      url    := 'https://api.callmebot.com/whatsapp.php',
      params := jsonb_build_object('phone', wa_to, 'apikey', wa_key, 'text', title || E'\n' || body));
  end if;

  if rs_key is not null and mail_to is not null then
    perform net.http_post(
      url     := 'https://api.resend.com/emails',
      body    := jsonb_build_object('from', 'ERP Leads <onboarding@resend.dev>', 'to', jsonb_build_array(mail_to),
                                    'subject', title, 'text', body || E'\n\nOpen: ' || dashboard),
      headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || rs_key));
  end if;
exception when others then
  -- A notification problem must never lose the client's request.
  raise warning 'lead alert failed: %', sqlerrm;
end $$;

create or replace function private.on_new_signup()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform private.send_lead_alert(new);
  return new;
end $$;

revoke all on function private.lead_secret(text)                  from public, anon, authenticated;
revoke all on function private.send_lead_alert(public.erp_signups) from public, anon, authenticated;
revoke all on function private.on_new_signup()                     from public, anon, authenticated;

drop trigger if exists erp_signups_notify on public.erp_signups;
create trigger erp_signups_notify
  after insert on public.erp_signups
  for each row execute function private.on_new_signup();


-- ---------------------------------------------------------------------
-- 4) Turn channels on (run only the lines you need, with your values).
--    To change a value later: update vault.secrets set secret = '...' where name = '...';
-- ---------------------------------------------------------------------
-- Phone push: install the "ntfy" app → Subscribe → enter this topic name.
-- select vault.create_secret('erp-leads-CHANGE-ME', 'lead_ntfy_topic');

-- WhatsApp (free, CallMeBot): from your WhatsApp send "I allow callmebot to send me messages"
-- to +34 644 66 32 62 — the reply contains your apikey.
-- select vault.create_secret('+201XXXXXXXXX', 'lead_whatsapp_phone');
-- select vault.create_secret('123456',        'lead_callmebot_apikey');

-- Email (free, Resend): sign up at resend.com with the email that should receive alerts,
-- create an API key, then:
-- select vault.create_secret('re_XXXXXXXX',        'lead_resend_api_key');
-- select vault.create_secret('you@example.com',    'lead_notify_email');


-- ---------------------------------------------------------------------
-- 5) Daily use
-- ---------------------------------------------------------------------
-- Newest requests:
--   select created_at, company_name, contact_name, phone, email, industry, modules, plan, status
--   from public.erp_signups order by created_at desc;
-- Mark one as contacted:
--   update public.erp_signups set status = 'contacted' where id = '...';
