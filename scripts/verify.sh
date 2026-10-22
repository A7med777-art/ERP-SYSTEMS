#!/usr/bin/env bash
# Checks that the published page matches index.html and that Supabase accepts
# sign-ups but refuses reads and tampered rows. Used by the Publish site workflow.
set -euo pipefail

SITE_URL=${SITE_URL:?}
SB_URL=$(grep -o "SB_URL='[^']*'" index.html | cut -d"'" -f2)
SB_KEY=$(grep -o "SB_KEY='[^']*'" index.html | cut -d"'" -f2)
PAGE_FILE=${PAGE_FILE:-index.html}
want=$(sha256sum "$PAGE_FILE" | cut -d' ' -f1)

echo "Waiting for $SITE_URL to serve this commit…"
for i in $(seq 1 40); do
  got=$(curl -fsSL "${SITE_URL}?v=${GITHUB_SHA:-$RANDOM}-$i" | sha256sum | cut -d' ' -f1 || true)
  if [ "$got" = "$want" ]; then echo "✓ live page matches the published file"; break; fi
  [ "$i" = 40 ] && { echo "✗ live page never matched index.html"; exit 1; }
  sleep 10
done

api() { curl -sS -o /tmp/body -w '%{http_code}' -H "apikey: $SB_KEY" -H 'Content-Type: application/json' "$@"; }

code=$(api "$SB_URL/rest/v1/erp_signups?select=id&limit=1")
[ "$code" = 401 ] || [ "$code" = 403 ] || { echo "✗ public read returned $code (expected refusal)"; cat /tmp/body; exit 1; }
echo "✓ visitors cannot read sign-ups ($code)"

code=$(api -X POST -H 'Prefer: return=minimal' "$SB_URL/rest/v1/erp_signups" \
  -d '{"modules":["sales"],"industry":"Retail","company_name":"x","contact_name":"x","email":"not-an-email"}')
[ "$code" = 400 ] || { echo "✗ invalid row returned $code (expected 400)"; cat /tmp/body; exit 1; }
echo "✓ invalid data is rejected by the database ($code)"

for verb in PATCH DELETE; do
  code=$(api -X "$verb" "$SB_URL/rest/v1/erp_signups?id=neq.00000000-0000-0000-0000-000000000000")
  [ "$code" = 401 ] || [ "$code" = 403 ] || { echo "✗ public $verb returned $code (expected refusal)"; cat /tmp/body; exit 1; }
  echo "✓ visitors cannot $verb requests ($code)"
done

page=$(curl -fsSL "${SITE_URL}?csp=${GITHUB_SHA:-x}")
grep -q 'http-equiv="Content-Security-Policy" content="default-src' <<<"$page" || { echo "✗ live page has no Content-Security-Policy"; exit 1; }
if grep -qiE 'service_role|sb_secret_' <<<"$page"; then echo "✗ a secret key is exposed in the page"; exit 1; fi
echo "✓ live page carries its security policy and no secret keys"

if [ "${INSERT_TEST:-false}" = true ]; then
  code=$(api -X POST -H 'Prefer: return=minimal' "$SB_URL/rest/v1/erp_signups" \
    -d '{"modules":["sales","inventory"],"industry":"Retail & E-commerce","company_name":"Deploy check (safe to delete)","contact_name":"GitHub Actions","email":"deploy-check@example.com","company_size":"1-10","plan":"growth"}')
  [ "$code" = 201 ] || { echo "✗ test sign-up returned $code"; cat /tmp/body; exit 1; }
  echo "✓ a real sign-up was accepted (201)"
fi
