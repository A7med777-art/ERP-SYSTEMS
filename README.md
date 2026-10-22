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

### GitHub Pages (free, live now)

Live at **https://a7med777-art.github.io/ERP-SYSTEMS/** (served from the `gh-pages` branch).

To change the site, edit `index.html` on the default branch (on github.com: open the file,
click the pencil, commit). The **Publish site** workflow copies it to `gh-pages`, waits until the
live page matches, and checks that Supabase still accepts sign-ups but refuses reads.
It takes about a minute; the result shows under the **Actions** tab.
Run the workflow manually with "Also send one real test sign-up" to test a full submission.

### Hetzner (optional, your own server)

1. Create a CX22 server (Ubuntu 24.04) and install Docker.
2. `git clone https://github.com/A7med777-art/ERP-SYSTEMS && cd ERP-SYSTEMS/deploy`
3. Free hostname without buying a domain: `<ip-with-dashes>.sslip.io`, e.g. `203-0-113-10.sslip.io`.
4. `DOMAIN=203-0-113-10.sslip.io docker compose up -d`

Caddy serves the static page with automatic HTTPS, gzip/zstd and security headers.
A single small instance comfortably serves thousands of concurrent visitors for one static file;
form traffic goes straight to Supabase.

## Database

`supabase/setup.sql` is the complete, re-runnable setup (table, rules, security, notifications).
Paste it into Supabase → SQL Editor → Run. It never drops the table or deletes rows.
`supabase/migrations/` keeps the original migration for history.

## New-request notifications

Every new row fires a database trigger (`private.on_new_signup`) that sends an alert through
`pg_net`. Channel keys live in Supabase Vault, never in the website:

| Channel | Vault secret names | Cost |
|---|---|---|
| Phone push (ntfy app) | `lead_ntfy_topic` | free, no account |
| WhatsApp (CallMeBot) | `lead_whatsapp_phone`, `lead_callmebot_apikey` | free |
| Email (Resend) | `lead_resend_api_key`, `lead_notify_email` | free tier |

See section 4 of `setup.sql` for the exact lines to turn each one on.
Delivery log: `select status_code, content, created from net._http_response order by created desc;`

## Custom subdomain

1. In Cloudflare (zone `concretech-trading.com`) → DNS → Add record:
   `CNAME  systems  →  a7med777-art.github.io` (Proxy status: DNS only).
2. Add a file named `CNAME` at the repo root containing `systems.concretech-trading.com`.
3. The Publish site workflow writes it to `gh-pages`; then Settings → Pages → tick "Enforce HTTPS".

## Security

Safe whether the repository is public or private: nothing in it is secret. The Supabase key in
`index.html` is the *publishable* key, which can only do what the database rules allow.

| Layer | Protection |
|---|---|
| Database | Visitors can only **add** a request: reading, editing, deleting, truncating and dropping are refused. Field lengths, email format, plan and module lists are enforced by the database. |
| Anti-spam | Max 10 requests/hour per internet address, 3/day per email, 3000/hour site-wide (`private.guard_signup`). Status, date and id are set by the server. Addresses are stored only as hashes. |
| Secrets | Notification keys live in Supabase Vault in the `private` schema, which the public key cannot reach. |
| Page | Strict Content-Security-Policy (only the page's own scripts by hash; data can go only to Supabase), no-referrer, refuses to run inside another site's frame, all user text rendered as plain text. |
| Pipeline | GitHub Actions pinned to exact versions, Dependabot for updates, each deploy checks the live site and the database rules. |

Run the attack test any time: paste `supabase/security_test.sql` into the SQL Editor — every row must say `PASS`.
After editing a `<script>` in `index.html`, run `python3 scripts/csp.py index.html` (the deploy also does it).
