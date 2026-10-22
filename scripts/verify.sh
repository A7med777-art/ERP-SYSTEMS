#!/usr/bin/env bash
# Checks that the published page matches index.html and that Supabase accepts
# sign-ups but refuses reads and tampered rows. Used by the Publish site workflow.
set -euo pipefail

SITE_URL=${SITE_URL:?}
SB_URL=$(grep -o "SB_URL='[^']*'" index.html | cut -d"'" -f2)
SB_KEY=$(grep -o "SB_KEY='[^']*'" index.html | cut -d"'" -f2)
want=$(sha256sum index.html | cut -d' ' -f1)

echo "Waiting for $SITE_URL to serve this commit…"
for i in $(seq 1 40); do
  got=$(curl -fsSL "${SITE_URL}?v=${GITHUB_SHA:-$RANDOM}-$i" | sha256sum | cut -d' ' -f1 || true)
  if [ "$got" = "$want" ]; then echo "✓ live page matches index.html"; break; fi
  [ "$i" = 40 ] && { echo "✗ live page never matched index.html"; exit 1; }
  sleep 10
done

api() { curl -sS -o /tmp/body -w '%{http_code}' -H "apikey: $SB_KEY" -H 'Content-Type: application/json' "$@"; }

code=$(api "$SB_URL/rest/v1/erp_signups?select=id&limit=1")
[ "$code" = 401 ] || [ "$code" = 403 ] || { echo "✗ public read returned $code (expected refusal)"; cat /tmp/body; exit 1; }
echo "✓ visitors cannot read sign-ups ($code)"

code=$(api -X POST -H 'Prefer: return=minimal' "$SB_URL/rest/v1/erp_signups" \
  -d '{"modules":["sales"],"industry":"Retail","company_name":"x","contact_name":"x","email":"x@example.com","status":"active"}')
[ "$code" = 401 ] || [ "$code" = 403 ] || { echo "✗ tampered row returned $code (expected refusal)"; cat /tmp/body; exit 1; }
echo "✓ visitors cannot insert rows with a forged status ($code)"

if [ "${INSERT_TEST:-false}" = true ]; then
  code=$(api -X POST -H 'Prefer: return=minimal' "$SB_URL/rest/v1/erp_signups" \
    -d '{"modules":["sales","inventory"],"industry":"Retail & E-commerce","company_name":"Deploy check (safe to delete)","contact_name":"GitHub Actions","email":"deploy-check@example.com","company_size":"1-10","plan":"growth"}')
  [ "$code" = 201 ] || { echo "✗ test sign-up returned $code"; cat /tmp/body; exit 1; }
  echo "✓ a real sign-up was accepted (201)"
fi
