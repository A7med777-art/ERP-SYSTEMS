-- Sign-up requests from the landing page (applied to the "Concretech ERP" project).
create table if not exists public.erp_signups (
  id             uuid primary key default gen_random_uuid(),
  created_at     timestamptz not null default now(),
  status         text not null default 'new'
                 check (status in ('new','contacted','onboarding','active','rejected')),
  plan           text not null default 'growth'
                 check (plan in ('starter','growth','enterprise')),
  modules        text[] not null check (cardinality(modules) between 1 and 20),
  industry       text not null check (char_length(industry) between 1 and 80),
  company_name   text not null check (char_length(company_name) between 1 and 160),
  contact_name   text not null check (char_length(contact_name) between 1 and 120),
  email          text not null check (char_length(email) <= 254 and email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  phone          text check (char_length(phone) <= 40),
  country        text check (char_length(country) <= 80),
  company_size   text check (company_size in ('1-10','11-50','51-200','201-1000','1000+')),
  current_system text check (char_length(current_system) <= 120),
  data_sources   text[] not null default '{}' check (cardinality(data_sources) <= 12),
  record_volume  text check (record_volume in ('<10k','10k-100k','100k-1m','1m+')),
  notes          text check (char_length(notes) <= 2000),
  locale         text check (char_length(locale) <= 20),
  user_agent     text check (char_length(user_agent) <= 400)
);

create index if not exists erp_signups_created_at_idx on public.erp_signups (created_at desc);
create index if not exists erp_signups_status_idx on public.erp_signups (status);

alter table public.erp_signups enable row level security;

-- The public site may only insert new requests; reading happens in the Supabase dashboard.
revoke all on table public.erp_signups from anon, authenticated;
grant insert on table public.erp_signups to anon, authenticated;

create policy "Anyone can submit a signup" on public.erp_signups
  for insert to anon, authenticated
  with check (status = 'new');
