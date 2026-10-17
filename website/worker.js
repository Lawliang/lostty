// lostty.org's one server route, copied into website/dist as _worker.js by
// build.mjs (Cloudflare Pages runs it in front of the static site).
//
// POST /api/endorse {"amount": cents} opens a Stripe Checkout for that many
// cents and answers {"url"}; the page then goes there. It uses the same Stripe
// account as idfk.app: the key is the Pages secret STRIPE_SECRET_KEY.
// Everything else is the static site.
const SESSIONS = "https://api.stripe.com/v1/checkout/sessions";
const MIN_CENTS = 100;
const MAX_CENTS = 500000;
// Marks checkouts this site created, among the account's other ones.
const PURPOSE = "lostty_endorse";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/api/endorse") return endorse(request, env, url.origin);
    return env.ASSETS.fetch(request);
  },
};

async function endorse(request, env, origin) {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" }, { Allow: "POST" });
  const body = await request.json().catch(() => null);
  const amount = body?.amount;
  if (!Number.isInteger(amount) || amount < MIN_CENTS || amount > MAX_CENTS) return json(400, { error: "bad_amount" });
  if (!env.STRIPE_SECRET_KEY) return json(503, { error: "not_configured" });
  const form = new URLSearchParams({
    mode: "payment",
    // Stripe's button reads "Donate"
    submit_type: "donate",
    "line_items[0][price_data][currency]": "usd",
    "line_items[0][price_data][unit_amount]": String(amount),
    "line_items[0][price_data][product_data][name]": "Endorse Lostty",
    "line_items[0][quantity]": "1",
    "metadata[purpose]": PURPOSE,
    success_url: `${origin}/?endorsed=1#support`,
    cancel_url: `${origin}/#support`,
  });
  const res = await fetch(SESSIONS, {
    method: "POST",
    headers: { Authorization: `Bearer ${env.STRIPE_SECRET_KEY}`, "Content-Type": "application/x-www-form-urlencoded" },
    body: form,
  }).catch(() => null);
  if (!res?.ok) return json(502, { error: "stripe_refused" });
  const { url } = await res.json();
  if (typeof url !== "string") return json(502, { error: "stripe_refused" });
  return json(200, { url });
}

function json(status, data, headers = {}) {
  return new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json", ...headers } });
}
