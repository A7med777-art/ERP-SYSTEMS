# ERP & CRM for Business Owners — landing page & client onboarding

Marketing site for custom ERP & CRM systems for business owners. A single self-contained
`index.html` (fonts embedded, no frameworks): fullscreen black stage,
graded looping video, one-shot entrance animation, mobile burger menu, and a 4-step onboarding
flow where clients choose **what to build** (modules), **their industry**, and **their data**,
then leave their company details.

Submissions are stored in Supabase, table `public.erp_signups`
(project *Concretech ERP*). The page uses the publishable key; Row Level Security only allows
**inserting** new requests — nobody can read, change or delete rows through the public API.

## See new sign-ups

Supabase dashboard → Table Editor → `erp_signups`, or SQL:

```sql
select created_at, company_name, contact_name, email, industry, modules, plan, company_size
from public.erp_signups order by created_at desc;
```

Move a lead through `status`: `new → contacted → onboarding → active` (or `rejected`).

## Hosting

### GitHub Pages (free subdomain, global CDN)

`.github/workflows/pages.yml` publishes `index.html` on every push.
One-time setup: **Settings → Pages → Build and deployment → Source: GitHub Actions**,
then re-run the workflow. The site is served at
`https://a7med777-art.github.io/ERP-SYSTEMS/`.

### Hetzner (optional, your own server)

1. Create a CX22 server (Ubuntu 24.04) and install Docker.
2. `git clone https://github.com/A7med777-art/ERP-SYSTEMS && cd ERP-SYSTEMS/deploy`
3. Free hostname without buying a domain: `<ip-with-dashes>.sslip.io`, e.g. `203-0-113-10.sslip.io`.
4. `DOMAIN=203-0-113-10.sslip.io docker compose up -d`

Caddy serves the static page with automatic HTTPS, gzip/zstd and security headers.
A single small instance comfortably serves thousands of concurrent visitors for one static file;
form traffic goes straight to Supabase.

## Database

`supabase/migrations/20261021000000_erp_signups.sql` is the schema that is already applied.
