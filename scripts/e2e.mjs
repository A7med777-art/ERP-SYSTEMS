// Real end-to-end test on the LIVE site, in a real browser (run by the "Live demo request" workflow).
// Opens the public link, fills the 5-step form like a client and submits it for real:
// the request is saved in Supabase and the notifications (push / email / WhatsApp) fire.
import { chromium } from "playwright";

const SITE_URL = process.env.SITE_URL;
const NAME = process.env.DEMO_NAME || "Live test";
const EMAIL = process.env.DEMO_EMAIL;
const PHONE = process.env.DEMO_PHONE || "";
if (!EMAIL) { console.error("DEMO_EMAIL is required"); process.exit(1); }

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1366, height: 768 } });
const problems = [];
page.on("pageerror", (e) => problems.push(e.message));
page.on("console", (m) => { if (m.type() === "error" && !/media|video|mp4/i.test(m.text())) problems.push(m.text()); });

const step = async (label, fn) => { await fn(); console.log("✓ " + label); };
const next = () => page.click("#jnav .btn-join");

await step(`Open ${SITE_URL}`, () => page.goto(SITE_URL, { waitUntil: "load" }));
await step("Arabic headline is visible", () => page.getByText("شغّل شركتك كلها").waitFor());
await step("Click \"ابنِ نظامك\"", () => page.click(".btn-cta"));
await step("Step 1 — pick modules", async () => {
  await page.check("input[value=sales]", { force: true });
  await page.check("input[value=inventory]", { force: true });
  await page.check("input[value=finance]", { force: true });
  await next();
});
await step("Step 2 — pick industry", async () => {
  await page.check('input[name=industry][value="Wholesale & Distribution"]', { force: true });
  await next();
});
await step("Step 3 — company data", async () => {
  await page.check('input[name=company_size][value="11-50"]', { force: true });
  await page.check("input[value=excel]", { force: true });
  await next();
});
await step("Step 4 — contact details", async () => {
  await page.fill("input[name=company_name]", "Live demo test (safe to delete)");
  await page.fill("input[name=contact_name]", NAME);
  await page.fill("input[name=email]", EMAIL);
  if (PHONE) await page.fill("input[name=phone]", PHONE);
  await page.fill("input[name=country]", "Egypt");
  await page.fill("textarea[name=notes]", "End-to-end test of the live site. Safe to delete.");
  await next();
});
await step("Step 5 — review shows the answers", () => page.getByText("Live demo test (safe to delete)").waitFor());
const [response] = await Promise.all([
  page.waitForResponse((r) => r.url().includes("/rest/v1/erp_signups"), { timeout: 20000 }),
  next(),
]);
console.log(`  Supabase answered ${response.status()}`);
await step("Confirmation \"طلبك وصل.\" appears", () => page.getByText("طلبك وصل.").waitFor({ timeout: 15000 }));
console.log("  Reference shown to the client: " + (await page.textContent("#jref-id")));
await page.screenshot({ path: "confirmation.png" });

await browser.close();
if (response.status() !== 201) { console.error("✗ expected 201 from Supabase"); process.exit(1); }
if (problems.length) { console.error("✗ page errors: " + problems.join(" | ")); process.exit(1); }
console.log("✓ Live demo request completed with no page errors");
