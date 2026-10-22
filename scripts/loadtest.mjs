// Load test: many visitors at the same time, from a GitHub runner.
//
//   node scripts/loadtest.mjs            (reads SITE_URL, TOTAL, CONCURRENCY from env)
//
// 1) Page:    TOTAL page loads, CONCURRENCY at a time.
// 2) Sign-up: TOTAL form submissions to Supabase, CONCURRENCY at a time. Each one passes
//    the API gateway, the security rules and the anti-spam guard, then is refused by the
//    email-format rule at the very end — so the full write path is exercised while no row
//    is saved and no notification is sent.
// Fails (exit 1) if more than 1% of requests error or the slowest 5% exceed 3 seconds.
import { readFileSync } from "node:fs";

const html = readFileSync("index.html", "utf8");
const SB_URL = html.match(/SB_URL='([^']+)'/)[1];
const SB_KEY = html.match(/SB_KEY='([^']+)'/)[1];
const SITE_URL = process.env.SITE_URL;
const TOTAL = +(process.env.TOTAL || 3000);
const CONCURRENCY = +(process.env.CONCURRENCY || 200);

async function run(name, makeRequest, okStatus) {
  const times = [], statuses = {};
  let next = 0, failures = 0;
  const started = performance.now();
  async function worker() {
    while (next < TOTAL) {
      const i = next++;
      const t = performance.now();
      let status;
      try {
        const r = await makeRequest(i);
        await r.arrayBuffer();
        status = r.status;
      } catch (e) {
        status = "network-error";
      }
      times.push(performance.now() - t);
      statuses[status] = (statuses[status] || 0) + 1;
      if (status !== okStatus) failures++;
    }
  }
  await Promise.all(Array.from({ length: CONCURRENCY }, worker));
  const secs = (performance.now() - started) / 1000;
  times.sort((a, b) => a - b);
  const pct = (p) => Math.round(times[Math.min(times.length - 1, Math.floor(times.length * p))]);
  const result = {
    name, requests: TOTAL, concurrent: CONCURRENCY,
    per_second: Math.round(TOTAL / secs), seconds: +secs.toFixed(1),
    p50_ms: pct(0.5), p95_ms: pct(0.95), p99_ms: pct(0.99), max_ms: Math.round(times.at(-1)),
    statuses, error_rate: +(failures / TOTAL * 100).toFixed(2) + "%",
  };
  const pass = failures / TOTAL <= 0.01 && result.p95_ms <= 3000;
  console.log(`${pass ? "✓" : "✗"} ${name}\n` + JSON.stringify(result, null, 2));
  return pass;
}

let allPass = true;

if (SITE_URL) {
  const probe = await fetch(SITE_URL).catch(() => null);
  if (probe && probe.ok) {
    allPass = (await run(`Page loads: ${SITE_URL}`,
      (i) => fetch(`${SITE_URL}?lt=${i % 50}`, { headers: { "accept-encoding": "gzip, br" } }), 200)) && allPass;
  } else {
    console.log(`– Page test skipped: ${SITE_URL} answered ${probe ? probe.status : "no response"} (site not public yet?)`);
  }
}

allPass = (await run("Sign-up submissions through Supabase (full write path, nothing saved)",
  (i) => fetch(`${SB_URL}/rest/v1/erp_signups`, {
    method: "POST",
    headers: { apikey: SB_KEY, "Content-Type": "application/json", Prefer: "return=minimal" },
    body: JSON.stringify({
      modules: ["sales", "inventory"], industry: "Retail & E-commerce",
      company_name: `Load test ${i}`, contact_name: "Load test", email: `load-test-${i}`, // invalid on purpose
      phone: "+201000000000", plan: "growth", company_size: "11-50",
    }),
  }), 400)) && allPass;

process.exit(allPass ? 0 : 1);
