/* Glimp admin. Reads everything through admin_* functions in backend/supabase.sql,
   which refuse anyone whose email isn't in site_admins. */
(() => {
  const CFG = window.GLIMP_CONFIG;
  const sb = supabase.createClient(CFG.supabaseUrl, CFG.supabaseKey, { auth: { persistSession: true, storageKey: "glimp-admin" } });
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => [...el.querySelectorAll(s)];
  const esc = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const inr = (paise) => "₹" + Math.round((paise || 0) / 100).toLocaleString("en-IN");
  const num = (n) => (n ?? 0).toLocaleString("en-IN");
  const pct = (a, b) => (b ? (100 * a / b) : 0);
  const fmtPct = (a, b) => (b ? pct(a, b).toFixed(pct(a, b) < 10 ? 1 : 0) + "%" : "—");
  const SWATCH = { black: "#2a2a2a", white: "#f2f2f0", red: "#d44b45", yellow: "#f2c230", blue: "#3060c8", lime: "#8fd13a", teal: "#2d8a78", grey: "#a5a5a5" };
  const LABEL = { hero: "Hero", colours_strip: "Colour strip", comparison: "Glimp vs others", keys: "On your keys", looks: "Six looks",
    sample_photos: "Photo wall", how_it_works: "How it works", app_keycam: "App", colours: "Shop / colours", whats_in_box: "In the box",
    quote: "Quote + note", faq: "FAQ", final_cta: "Pick yours", footer: "Footer" };

  const toast = (t) => { const el = $("[data-toast]"); el.textContent = t; el.hidden = false; clearTimeout(toast.t); toast.t = setTimeout(() => (el.hidden = true), 2600); };
  const call = async (fn, args) => {
    const { data, error } = await sb.rpc(fn, args);
    if (error) { toast(error.message.includes("not allowed") ? "This account isn't an admin." : "Error: " + error.message); throw error; }
    return data;
  };

  /* ---------- auth ---------- */
  async function boot() {
    const { data: { session } } = await sb.auth.getSession();
    if (!session) return show("login");
    const { data: ok } = await sb.rpc("is_site_admin");
    if (!ok) { await sb.auth.signOut(); show("login"); msg("This account isn't on the admin list. See ORDERS-SETUP.md step 3."); return; }
    show("app");
    // your own visits shouldn't count in the numbers
    if (!document.cookie.includes("glimp_int=1")) document.cookie = "glimp_int=1; Max-Age=31536000; Path=/; SameSite=Lax" + (location.protocol === "https:" ? "; Secure" : "");
    load();
  }
  const show = (v) => $$("[data-view]").forEach((el) => (el.hidden = el.dataset.view !== v));
  const msg = (t) => { const m = $("[data-login-msg]"); m.textContent = t; m.hidden = !t; };
  $("[data-login]").addEventListener("submit", async (e) => {
    e.preventDefault();
    const f = new FormData(e.target);
    msg("");
    const { error } = await sb.auth.signInWithPassword({ email: f.get("email"), password: f.get("password") });
    if (error) return msg("Wrong email or password.");
    boot();
  });
  $("[data-signout]").addEventListener("click", async () => { await sb.auth.signOut(); show("login"); });

  /* ---------- tabs + range ---------- */
  let tab = "overview";
  $$("[data-tab]").forEach((b) => b.addEventListener("click", () => {
    tab = b.dataset.tab;
    $$("[data-tab]").forEach((x) => x.setAttribute("aria-selected", x === b));
    $$("[data-pane]").forEach((p) => (p.hidden = p.dataset.pane !== tab));
    load();
  }));
  $("[data-range]").addEventListener("change", () => load());
  function range() {
    const v = +$("[data-range]").value;
    const ist = new Date(Date.now() + 5.5 * 3600e3).toISOString().slice(0, 10);
    const d = (s, k) => new Date(new Date(s + "T00:00:00Z").getTime() - k * 86400e3).toISOString().slice(0, 10);
    if (v === 0) return [ist, ist];
    if (v === 1) return [d(ist, 1), d(ist, 1)];
    return [d(ist, v - 1), ist];
  }

  let dash = null;
  async function load() {
    if (tab === "orders") return loadOrders();
    if (tab === "stock") return loadStock();
    const [from, to] = range();
    dash = await call("admin_dashboard", { p_from: from, p_to: to });
    const tc = $("[data-tocall]"); tc.textContent = dash.kpi.to_call; tc.hidden = !dash.kpi.to_call;
    tab === "overview" ? renderOverview(dash) : renderBehaviour(dash);
  }

  /* ---------- small renderers ---------- */
  const delta = (cur, prev) => {
    if (!prev) return "";
    const d = ((cur - prev) / prev) * 100;
    return `<span class="${d >= 0 ? "up" : "down"}">${d >= 0 ? "▲" : "▼"} ${Math.abs(d).toFixed(0)}%</span> vs previous`;
  };
  const kpi = (label, value, sub = "", cls = "") => `<div class="card kpi ${cls}"><div class="label">${label}</div><div class="v">${value}</div><div class="s">${sub}</div></div>`;
  const rate = (label, a, b, sub = "") => kpi(label, fmtPct(a, b), `${sub}${sub ? " · " : ""}n = ${num(b)}${b < 100 ? " · small sample" : ""}`, b < 100 ? "dim" : "");
  const table = (cols, rows) => rows.length ? `<div class="scroll"><table class="tbl"><thead><tr>${cols.map((c) => `<th class="${c[2] || ""}">${c[0]}</th>`).join("")}</tr></thead><tbody>${
    rows.map((r) => `<tr>${cols.map((c) => `<td class="${c[2] || ""}">${c[1](r)}</td>`).join("")}</tr>`).join("")}</tbody></table></div>` : `<p class="empty">Nothing yet.</p>`;
  const bars = (items, max, cls = "") => items.length ? `<div class="bars ${cls}">${items.map((i) =>
    `<div class="bar"><span>${esc(i.label)}</span><span class="track"><span class="fill ${i.accent ? "accent" : ""}" style="width:${max ? Math.max(1.5, 100 * i.value / max) : 0}%"></span></span><span class="num">${i.text ?? num(i.value)}</span></div>`).join("")}</div>` : `<p class="empty">Nothing yet.</p>`;

  function chart(daily) {
    if (!daily.length) return "";
    const W = 600, H = 170, pad = 22, n = daily.length;
    const maxS = Math.max(1, ...daily.map((d) => d.sessions)), maxO = Math.max(1, ...daily.map((d) => d.orders));
    const bw = (W - pad) / n;
    const barsSvg = daily.map((d, i) => {
      const h = (H - pad) * d.sessions / maxS;
      return `<rect x="${pad + i * bw + bw * .15}" y="${H - pad - h}" width="${bw * .7}" height="${h}" rx="2" fill="currentColor" opacity=".85"><title>${d.day}: ${d.sessions} sessions, ${d.orders} orders</title></rect>`;
    }).join("");
    const pts = daily.map((d, i) => `${pad + i * bw + bw / 2},${H - pad - (H - pad) * .92 * d.orders / maxO}`).join(" ");
    const lbl = (i) => daily[i].day.slice(5).replace("-", "/");
    const ticks = n > 1 ? `<text x="${pad}" y="${H - 4}" font-size="10" fill="currentColor" opacity=".6">${lbl(0)}</text><text x="${W}" y="${H - 4}" font-size="10" text-anchor="end" fill="currentColor" opacity=".6">${lbl(n - 1)}</text>` : "";
    return `<div class="chart"><svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="none" role="img" aria-label="Sessions and orders by day">
      <text x="0" y="10" font-size="10" fill="currentColor" opacity=".6">${maxS}</text>${barsSvg}
      <polyline points="${pts}" fill="none" stroke="#e0662a" stroke-width="2"/>${daily.map((d, i) => d.orders ? `<circle cx="${pad + i * bw + bw / 2}" cy="${H - pad - (H - pad) * .92 * d.orders / maxO}" r="3.5" fill="#e0662a"/>` : "").join("")}${ticks}</svg>
      <div class="legend label"><span>Sessions</span><span class="o">Orders (max ${maxO})</span></div></div>`;
  }

  /* ---------- overview ---------- */
  function renderOverview(d) {
    const k = d.kpi, p = d.prev;
    const spend = k.spend_paise, deliv = k.delivered;
    const funnelMax = d.funnel[0].n || 1;
    $("[data-pane=overview]").innerHTML = `
      <div class="grid g-kpi">
        ${kpi("Sessions", num(k.sessions), delta(k.sessions, p.sessions))}
        ${kpi("Visitors", num(k.visitors), `${fmtPct(k.consented, k.sessions)} accepted cookies`)}
        ${rate("Session conversion", k.sessions_converted, k.sessions)}
        ${kpi("Orders", num(k.orders), delta(k.orders, p.orders) || `${num(k.units)} cameras`)}
        ${kpi("To call", num(k.to_call), "orders waiting", k.to_call ? "hi" : "")}
        ${kpi("Delivered", num(deliv), `${inr(k.delivered_paise)} collected`)}
        ${kpi("Revenue placed", inr(k.gross_paise), `${num(k.orders)} orders`)}
        ${rate("RTO rate", k.rto, k.shipped, "of shipped")}
        ${kpi("Ad spend", inr(spend), spend ? "" : "add it on Stock tab")}
        ${kpi("CAC (delivered)", deliv && spend ? inr(spend / deliv) : "—", "spend ÷ delivered")}
        ${kpi("ROAS (delivered)", spend ? (k.delivered_paise / spend).toFixed(2) + "×" : "—", "delivered ₹ ÷ spend")}
        ${kpi("Live now", num(d.live), "last 5 minutes")}
      </div>
      <div class="section-gap"></div>
      <div class="grid g-2">
        <div class="card"><h3>Sessions & orders by day</h3>${chart(d.daily)}</div>
        <div class="card funnel"><h3>Funnel</h3>${bars(d.funnel.map((s, i) => ({ label: s.step, value: s.n,
          text: `${num(s.n)} · ${i ? fmtPct(s.n, d.funnel[i - 1].n) : "100%"}`, accent: i >= 3 })), funnelMax)}
          <p class="empty" style="margin-top:10px">% = of the step above. Sessions → Ordered is session-based; the last three steps count orders.</p></div>
      </div>
      <div class="section-gap"></div>
      <div class="grid g-2">
        <div class="card"><h3>Channels</h3>${table([
          ["Channel", (r) => esc(r.channel)], ["Sessions", (r) => num(r.sessions), "n"], ["Engaged", (r) => fmtPct(r.engaged, r.sessions), "n"],
          ["Opened form", (r) => num(r.checkouts), "n"], ["Ordered", (r) => num(r.converted), "n"], ["CR", (r) => fmtPct(r.converted, r.sessions), "n"]], d.channels)}</div>
        <div class="card"><h3>Colours</h3>${table([
          ["Colour", (r) => `<span class="dot" style="background:${SWATCH[r.colour]}"></span>${esc(r.colour)}`], ["Picked", (r) => num(r.picked), "n"],
          ["Form", (r) => num(r.checkouts), "n"], ["Orders", (r) => num(r.units), "n"], ["Delivered", (r) => num(r.delivered), "n"],
          ["In stock", (r) => `<span class="${r.on_hand <= 0 ? "down" : r.on_hand <= r.low_at ? "" : ""}">${num(r.on_hand)}</span>`, "n"],
          ["Waiting", (r) => num(r.waiting), "n"]], d.colours)}</div>
      </div>
      <div class="section-gap"></div>
      <div class="grid g-2">
        <div class="card"><h3>Ads (utm_campaign / utm_content)</h3>${table([
          ["Campaign", (r) => esc(r.campaign)], ["Ad", (r) => esc(r.ad)], ["Sessions", (r) => num(r.sessions), "n"],
          ["Bounce", (r) => fmtPct(r.bounces, r.sessions), "n"], ["Ordered", (r) => num(r.converted), "n"], ["CR", (r) => fmtPct(r.converted, r.sessions), "n"]], d.campaigns)}</div>
        <div class="card"><h3>Devices · States</h3>${table([
          ["Device", (r) => esc(r.device)], ["Sessions", (r) => num(r.sessions), "n"], ["CR", (r) => fmtPct(r.converted, r.sessions), "n"]], d.devices)}
          <div class="section-gap"></div>${table([["State", (r) => esc(r.state)], ["Orders", (r) => num(r.orders), "n"], ["RTO", (r) => num(r.rto), "n"]], d.states)}</div>
      </div>`;
  }

  /* ---------- behaviour ---------- */
  function renderBehaviour(d) {
    const S = d.kpi.sessions || 0;
    const secMax = Math.max(1, ...d.sections.map((s) => s.reached));
    const faqMax = Math.max(1, ...d.faq.map((f) => f.sessions));
    const lookMax = Math.max(1, ...d.looks.map((l) => l.n));
    const tabMax = Math.max(1, ...d.app_tabs.map((l) => l.n));
    const exitMax = Math.max(1, ...d.exit_sections.map((l) => l.n));
    const scrollMax = Math.max(1, ...d.scroll.map((l) => l.sessions));
    const sp = d.speed || {};
    $("[data-pane=behaviour]").innerHTML = `
      <div class="grid g-kpi">
        ${rate("Engaged sessions", d.kpi.engaged, S)}
        ${rate("Bounce rate", d.kpi.bounces, S)}
        ${kpi("Avg engaged time", d.kpi.avg_engaged_s ? d.kpi.avg_engaged_s + " s" : "—", "visible tab time")}
        ${kpi("Forms abandoned", num(d.abandoned), "typed, then closed")}
        ${kpi("LCP p75", sp.lcp_p75_ms ? (sp.lcp_p75_ms / 1000).toFixed(1) + " s" : "—", sp.lcp_p75_ms > 2500 ? "slow: aim under 2.5 s" : "page load speed", sp.lcp_p75_ms > 2500 ? "hi" : "")}
        ${kpi("Layout shift p75", sp.cls_p75 != null ? Number(sp.cls_p75).toFixed(2) : "—", "aim under 0.1")}
      </div>
      <div class="section-gap"></div>
      <div class="grid g-2">
        <div class="card"><h3>How far people get (section reached)</h3>${bars(d.sections.map((s) => ({ label: LABEL[s.section] || s.section, value: s.reached, text: `${fmtPct(s.reached, S)} of sessions` })), secMax)}</div>
        <div class="card"><h3>Last section seen before leaving (no order form)</h3>${bars(d.exit_sections.map((s) => ({ label: LABEL[s.section] || s.section, value: s.n, accent: true })), exitMax)}
          <div class="section-gap"></div><h3>Scroll depth</h3>${bars(d.scroll.map((s) => ({ label: s.depth + "%", value: s.sessions, text: fmtPct(s.sessions, S) })), scrollMax)}</div>
      </div>
      <div class="section-gap"></div>
      <div class="grid g-2">
        <div class="card"><h3>Worries (FAQ opened)</h3>${bars(d.faq.map((f) => ({ label: f.faq, value: f.sessions,
            text: `${num(f.sessions)}${f.lift ? ` · lift ${f.lift}` : ""}`, accent: f.lift > 1.5 })), faqMax)}
          <p class="empty" style="margin-top:10px">Lift = how much more often people who didn’t open the order form read it. Above 1.5 (orange) means it worries non-buyers.</p></div>
        <div class="card"><h3>Looks tried</h3>${bars(d.looks.map((l) => ({ label: l.look, value: l.n })), lookMax)}
          <div class="section-gap"></div><h3>App uses tapped</h3>${bars(d.app_tabs.map((l) => ({ label: l.usecase, value: l.n })), tabMax)}</div>
      </div>
      <div class="section-gap"></div>
      <div class="grid g-2">
        <div class="card"><h3>Order form errors</h3>${table([["Field", (r) => esc(r.field)], ["Problem", (r) => esc(r.error_type)], ["Count", (r) => num(r.n), "n"]], d.field_errors)}</div>
        <div class="card"><h3>Frustration (rage clicks, errors)</h3>${table([["Kind", (r) => esc(r.kind)], ["Where / what", (r) => esc(r.what)], ["Count", (r) => num(r.n), "n"]], d.frustration)}
          ${CFG.clarityId ? `<p style="margin-top:10px"><a href="https://clarity.microsoft.com/projects/view/${esc(CFG.clarityId)}/dashboard" target="_blank" rel="noopener">Open heatmaps and recordings in Clarity ›</a></p>` : ""}</div>
      </div>
      <div class="section-gap"></div>
      <div class="card"><h3>Cancel and RTO reasons</h3>${table([["Status", (r) => esc(r.status)], ["Reason", (r) => esc(r.reason)], ["Count", (r) => num(r.n), "n"]], d.cancel_reasons)}</div>
      <div class="section-gap"></div>
      <div class="card"><h3>Data health</h3>
        <p>Events in the last 24 h: <b>${num(d.health.events_24h)}</b> · Rejected: ${Object.entries(d.health.rejected_24h).map(([k, v]) => `${esc(k)} ${num(v)}`).join(", ") || "none"}</p>
        <p>Orders seen by the browser: <b>${num(d.health.browser_orders)}</b> · in the database: <b>${num(d.health.server_orders)}</b>
          ${d.health.server_orders && Math.abs(d.health.browser_orders - d.health.server_orders) / d.health.server_orders > .1 ? " · gap over 10% (ad blockers, or people who declined cookies)" : ""}</p></div>`;
  }

  /* ---------- orders ---------- */
  let filter = "created";
  $$("[data-order-filter] button").forEach((b) => b.addEventListener("click", () => {
    filter = b.dataset.f;
    $$("[data-order-filter] button").forEach((x) => x.setAttribute("aria-pressed", x === b));
    loadOrders();
  }));
  const CANCEL = [["changed_mind", "Changed mind"], ["price", "Price"], ["delivery_too_late", "Too slow"], ["unreachable", "Unreachable"],
    ["fake_order", "Fake order"], ["duplicate", "Duplicate"], ["other", "Other"]];
  const RTO = [["refused", "Refused at door"], ["unreachable", "Not reachable"], ["wrong_address", "Wrong address"], ["other", "Other"]];
  const sel = (name, opts) => `<select name="${name}">${opts.map(([v, t]) => `<option value="${v}">${t}</option>`).join("")}</select>`;
  function actions(o) {
    const s = o.status;
    const a = [];
    if (s === "created") a.push(
      `<button class="btn sm" data-act="confirm">Confirmed</button>`,
      `<button class="btn sm ghost" data-act="no_answer">No answer</button>`,
      `<button class="btn sm ghost" data-act="reschedule">Call later</button>`);
    if (s === "created" || s === "confirmed") a.push(
      `<span class="o-acts">${sel("courier", [["", "Courier"], ["India Post", "India Post"], ["Delhivery", "Delhivery"], ["Shiprocket", "Shiprocket"], ["DTDC", "DTDC"], ["Other", "Other"]])}
       <input name="awb" placeholder="Tracking no." size="12"><button class="btn sm${s === "confirmed" ? "" : " ghost"}" data-act="ship">Shipped</button></span>`,
      `<span class="o-acts">${sel("reason", CANCEL)}<button class="btn sm warn" data-act="cancel">Cancel</button></span>`);
    if (s === "shipped") a.push(`<button class="btn sm" data-act="deliver">Delivered</button>`,
      `<span class="o-acts">${sel("reason", RTO)}<button class="btn sm warn" data-act="rto">RTO</button></span>`);
    if (s === "delivered") a.push(`<button class="btn sm ghost" data-act="return">Returned</button>`);
    a.push(`<button class="link" data-act="toggle_test">${o.is_test ? "Not a test" : "Mark as test"}</button>`);
    return a.join("");
  }
  async function loadOrders() {
    const list = await call("admin_orders", { p_status: filter || null, p_limit: 300 });
    const box = $("[data-orders]");
    if (!list.length) { box.innerHTML = `<p class="empty">No orders here.</p>`; return; }
    box.innerHTML = list.map((o) => {
      const when = new Date(o.created_at).toLocaleString("en-IN", { timeZone: "Asia/Kolkata", day: "numeric", month: "short", hour: "numeric", minute: "2-digit" });
      const wa = `https://wa.me/91${o.phone}?text=${encodeURIComponent(`Hi ${o.name.split(" ")[0]}, this is Yash from Glimp about your order ${o.order_no}.`)}`;
      const addr = `${o.address}, ${o.city}, ${o.state} ${o.pincode}`;
      return `<article class="order${o.is_test ? " test" : ""}" data-no="${esc(o.order_no)}">
        <div class="o-head"><span class="o-no">${esc(o.order_no)} · ${when}</span>
          <span class="o-meta"><span class="tag st-${esc(o.status)}">${esc(o.status)}</span>${o.call_attempts ? `<span class="tag">${o.call_attempts} call${o.call_attempts > 1 ? "s" : ""}${o.last_call_outcome ? " · " + esc(o.last_call_outcome) : ""}</span>` : ""}${o.is_test ? `<span class="tag">test</span>` : ""}</span></div>
        <div><span class="o-who">${esc(o.name)}</span> · <a href="tel:+91${esc(o.phone)}">+91 ${esc(o.phone)}</a> · <a href="${wa}" target="_blank" rel="noopener">WhatsApp</a></div>
        <div class="o-addr">${esc(addr)} <button class="link" data-copy="${esc(`${o.name}\n${addr}\n+91 ${o.phone}`)}">Copy</button></div>
        <div class="o-meta"><span class="tag"><span class="dot" style="background:${SWATCH[o.colour]}"></span>${o.qty} × ${esc(o.colour)}</span><span class="tag">${inr(o.value_paise)} COD</span>
          ${o.channel ? `<span class="tag">${esc(o.channel)}</span>` : ""}${o.courier ? `<span class="tag">${esc(o.courier)} ${esc(o.awb || "")}</span>` : ""}</div>
        ${o.note ? `<div class="o-addr">Note: ${esc(o.note)}</div>` : ""}
        <div class="o-acts">${actions(o)}</div></article>`;
    }).join("");
  }
  $("[data-orders]").addEventListener("click", async (e) => {
    const copy = e.target.closest("[data-copy]");
    if (copy) { navigator.clipboard?.writeText(copy.dataset.copy); toast("Address copied"); return; }
    const b = e.target.closest("[data-act]"); if (!b) return;
    const card = b.closest("[data-no]"), grp = b.closest(".o-acts span") || b.parentElement;
    const reason = $("[name=reason]", grp)?.value || null;
    const courier = $("[name=courier]", grp)?.value || null, awb = $("[name=awb]", grp)?.value || null;
    if (b.dataset.act === "cancel" && !confirm("Cancel this order? Its stock goes back on the shelf.")) return;
    b.disabled = true;
    try {
      const r = await call("admin_order_action", { p_order_no: card.dataset.no, p_action: b.dataset.act, p_reason: reason, p_courier: courier, p_awb: awb });
      if (!r.ok) { toast(r.error === "bad_transition" ? `Can't do that from "${r.status}"` : "Didn't work: " + r.error); b.disabled = false; return; }
      toast(r.restocked ? "Done. Stock returned." : "Done.");
      loadOrders();
    } catch { b.disabled = false; }
  });

  /* ---------- stock ---------- */
  async function loadStock() {
    const v = await call("admin_stock_view");
    const today = new Date(Date.now() + 5.5 * 3600e3).toISOString().slice(0, 10);
    $("[data-pane=stock]").innerHTML = `
      <div class="card"><h3>Stock by colour</h3>
        <div class="stock-row label"><span>Colour</span><span>On hand</span><span class="hide-m">To ship</span><span class="hide-m">Waiting</span><span>Change</span></div>
        ${v.stock.map((s) => `<div class="stock-row">
          <span><span class="dot" style="background:${SWATCH[s.colour]}"></span>${esc(s.colour)}</span>
          <span class="big ${s.on_hand <= 0 ? "out" : s.on_hand <= s.low_at ? "low" : ""}">${num(s.on_hand)}</span>
          <span class="hide-m">${num(s.to_ship)}</span><span class="hide-m">${num(s.waiting)}</span>
          <form data-stock="${esc(s.colour)}"><input name="n" type="number" min="0" step="1" inputmode="numeric" placeholder="0" required>
            <button class="btn sm" data-mode="add">Add</button><button class="btn sm ghost" data-mode="set">Set to</button></form></div>`).join("")}
        <p class="empty">On hand = cameras you can still sell. Orders take stock out; cancelled and RTO orders put it back.</p></div>
      <div class="section-gap"></div>
      <div class="grid g-2">
        <div class="card"><h3>Waiting for a sold-out colour</h3>${table([
          ["Colour", (r) => esc(r.colour)], ["Phone", (r) => `<a href="https://wa.me/91${esc(r.phone)}" target="_blank" rel="noopener">+91 ${esc(r.phone)}</a>`],
          ["Since", (r) => new Date(r.created_at).toLocaleDateString("en-IN", { timeZone: "Asia/Kolkata", day: "numeric", month: "short" })],
          ["", (r) => `<button class="link" data-notified="${r.id}">Messaged</button>`]], v.waiting)}</div>
        <div class="card"><h3>Meta ad spend</h3>
          <form class="o-acts" data-spend><input name="date" type="date" value="${today}" required><input name="rupees" type="number" min="0" step="1" placeholder="₹ spent" required><button class="btn sm">Save</button></form>
          <div class="section-gap"></div>${table([["Date", (r) => esc(r.date)], ["Spend", (r) => inr(r.spend_paise), "n"]], v.spend)}
          <p class="empty">From Ads Manager → Amount spent, per day. Used for CAC and ROAS.</p></div>
      </div>
      <div class="section-gap"></div>
      <div class="card"><h3>Stock history</h3>${table([
        ["When", (r) => new Date(r.created_at).toLocaleString("en-IN", { timeZone: "Asia/Kolkata", day: "numeric", month: "short", hour: "numeric", minute: "2-digit" })],
        ["Colour", (r) => esc(r.colour)], ["Change", (r) => `<span class="${r.delta > 0 ? "up" : "down"}">${r.delta > 0 ? "+" : ""}${r.delta}</span>`, "n"],
        ["Why", (r) => esc(r.reason) + (r.order_no ? " · " + esc(r.order_no) : "") + (r.note ? " · " + esc(r.note) : "")]], v.moves)}</div>`;
  }
  $("[data-pane=stock]").addEventListener("click", async (e) => {
    const mode = e.target.closest("[data-mode]");
    if (mode) {
      e.preventDefault();
      const f = mode.closest("form"), n = parseInt(f.elements.n.value, 10);
      if (!(n >= 0)) return toast("Type a number first");
      if (mode.dataset.mode === "set" && !confirm(`Set ${f.dataset.stock} to exactly ${n}?`)) return;
      const r = await call("admin_stock", { p_colour: f.dataset.stock, p_mode: mode.dataset.mode, p_n: n, p_note: null });
      toast(r.ok ? `${f.dataset.stock}: ${r.on_hand} on hand` : "Didn't work");
      loadStock();
    }
    const nb = e.target.closest("[data-notified]");
    if (nb) { await call("admin_restock_notified", { p_id: +nb.dataset.notified }); loadStock(); }
  });
  $("[data-pane=stock]").addEventListener("submit", async (e) => {
    if (!e.target.matches("[data-spend]")) return;
    e.preventDefault();
    const f = e.target;
    await call("admin_set_spend", { p_date: f.elements.date.value, p_rupees: +f.elements.rupees.value });
    toast("Spend saved"); loadStock();
  });

  // refresh the numbers every minute while the tab is open
  // (not on Orders or Stock: that would wipe a half-typed tracking number)
  setInterval(() => { if (document.visibilityState === "visible" && !$("[data-view=app]").hidden && (tab === "overview" || tab === "behaviour")) load(); }, 60000);
  boot();
})();
