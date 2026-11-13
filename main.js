/* Glimp site behaviour. No libraries. Settings live in config.js. */
const CFG = window.GLIMP_CONFIG || {};
const PRICE = 1490;
const COLOURS = [
  ["black", "Black"], ["white", "White"], ["red", "Red"], ["yellow", "Yellow"],
  ["blue", "Blue"], ["lime", "Lime"], ["teal", "Teal"], ["grey", "Grey"],
];
const ANGLES = { black: 10, white: 10, red: 10, yellow: 10, blue: 9, lime: 9, teal: 10, grey: 10 };

/* Sample photos for the wall: [file, caption]. Swap for real Glimp shots in assets/photos. */
const PHOTOS = [
  ["01", "Monsoon walk"], ["02", "Tea stall"], ["03", "Auto, 9am"], ["04", "Local train"], ["05", "Chai + rusk"],
  ["06", "Building dog"], ["07", "Beach shacks"], ["08", "Low tide"], ["09", "Church by the sea"], ["10", "Shack lights"],
  ["11", "Thali"], ["12", "Two cuttings"], ["13", "Sea face"], ["14", "New café"], ["15", "Old city"],
  ["16", "Rangoli"], ["17", "Diyas"],
];

const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const nameOf = (c) => COLOURS.find(([k]) => k === c)[1];
const inr = (n) => "₹" + n.toLocaleString("en-IN");
const track = (...a) => window.glimp?.track(...a);

/* ---------- Supabase RPC (public functions only) ---------- */
async function rpc(fn, body) {
  if (!CFG.supabaseUrl) throw new Error("no backend");
  const res = await fetch(`${CFG.supabaseUrl}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", apikey: CFG.supabaseKey },
    body: JSON.stringify(body || {}),
  });
  if (!res.ok) { track("api_error", { endpoint: fn, status: res.status }); throw new Error(fn + " " + res.status); }
  return res.json();
}

/* ---------- stock ---------- */
let STOCK = {};                                   // {teal: {status:'in'|'low'|'out', left}}
const stockOf = (c) => STOCK[c]?.status || "in";
async function loadStock() {
  try { STOCK = await rpc("get_stock"); } catch { STOCK = {}; }
  paintStock();
}
function paintStock() {
  $$("[data-swatch]").forEach((b) => b.classList.toggle("out", stockOf(b.dataset.swatch) === "out"));
  $$("#o-colour option").forEach((o) => { o.disabled = stockOf(o.value) === "out"; o.textContent = nameOf(o.value) + (o.disabled ? " (sold out)" : ""); });
  setColour(colour, false, true);
}

/* ---------- colour + angle gallery ---------- */
let colour = "black", angle = 1;
function showAngle(n, user) {
  const max = ANGLES[colour];
  angle = ((n - 1 + max) % max) + 1;
  const img = $("[data-gallery-img]");
  const next = new Image(); next.src = `assets/gallery/${colour}/${angle}.webp`;
  img.style.opacity = .25;
  next.decode().catch(() => {}).finally(() => {
    img.src = next.src; img.alt = `Glimp in ${nameOf(colour)}, view ${angle} of ${max}`; img.style.opacity = 1;
  });
  $("[data-g-count]").textContent = `${angle} / ${max}`;
  $$("[data-thumb]").forEach((t) => t.setAttribute("aria-current", +t.dataset.thumb === angle));
  // scroll only the thumbnail row sideways (scrollIntoView would also scroll the page)
  const cur = $(`[data-thumb="${angle}"]`), row = $("[data-gallery-thumbs]");
  if (cur) row.scrollTo({ left: cur.offsetLeft - row.clientWidth / 2 + cur.clientWidth / 2, behavior: user ? "smooth" : "auto" });
  if (user) track("product_image_viewed", { image_index: angle, image_kind: "product", colour });
}
function buildThumbs() {
  const max = ANGLES[colour];
  $("[data-gallery-thumbs]").innerHTML = Array.from({ length: max }, (_, i) =>
    `<button type="button" class="thumb" data-thumb="${i + 1}" aria-label="View ${i + 1}">
       <img src="assets/gallery/${colour}/${i + 1}-sm.webp" alt="" width="240" height="150" loading="lazy"></button>`).join("");
}
function setColour(c, user, keepAngle) {
  const from = colour;
  const changed = c !== colour;
  colour = c;
  if (changed || !$("[data-thumb]")) { buildThumbs(); }
  showAngle(changed || !keepAngle ? 1 : angle, false);
  $("[data-colour-name]").textContent = nameOf(c);
  const st = STOCK[c], note = $("[data-stock-note]");
  note.textContent = st?.status === "out" ? "Sold out" : st?.status === "low" && st.left ? `Only ${st.left} left` : "";
  note.className = "stock " + (st?.status || "");
  const buy = $("[data-buy-selected]");
  buy.firstChild.textContent = stockOf(c) === "out" ? `Notify me when ${nameOf(c)} is back ` : `Order ${nameOf(c)} — ₹1,490 `;
  buy.classList.toggle("ghost", stockOf(c) === "out");
  $$("[data-swatch]").forEach((b) => { const on = b.dataset.swatch === c; b.setAttribute("aria-checked", on); b.tabIndex = on ? 0 : -1; });
  if (user && changed) track("colour_swatch_selected", { from_colour: from, to_colour: c, in_stock: stockOf(c) !== "out" });
}
function wireShop() {
  const wrap = $("[data-swatches]");
  wrap.innerHTML = COLOURS.map(([k, n]) =>
    `<button class="swatch" role="radio" aria-checked="false" aria-label="${n}" title="${n}" data-swatch="${k}">
       <img src="assets/gallery/${k}/1-sm.webp" alt="" width="240" height="150" loading="lazy"></button>`).join("");
  wrap.addEventListener("click", (e) => { const b = e.target.closest("[data-swatch]"); if (b) setColour(b.dataset.swatch, true); });
  wrap.addEventListener("keydown", (e) => {
    const d = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[e.key];
    if (!d) return;
    e.preventDefault();
    const i = COLOURS.findIndex(([k]) => k === colour);
    setColour(COLOURS[(i + d + COLOURS.length) % COLOURS.length][0], true);
    $(`[data-swatch="${colour}"]`).focus();
  });
  $("[data-gallery-thumbs]").addEventListener("click", (e) => { const t = e.target.closest("[data-thumb]"); if (t) showAngle(+t.dataset.thumb, true); });
  $$("[data-g]").forEach((b) => b.addEventListener("click", () => showAngle(angle + +b.dataset.g, true)));
  // swipe on the big image
  const main = $(".gallery-main"); let x0 = null;
  main.addEventListener("pointerdown", (e) => { x0 = e.clientX; });
  main.addEventListener("pointerup", (e) => { if (x0 !== null && Math.abs(e.clientX - x0) > 40) showAngle(angle + (e.clientX < x0 ? 1 : -1), true); x0 = null; });
  main.addEventListener("keydown", (e) => { if (e.key === "ArrowRight") showAngle(angle + 1, true); if (e.key === "ArrowLeft") showAngle(angle - 1, true); });
  setColour("black");

  // product_viewed: the shop came into view (an essential event, counted even without consent)
  let viewed = false;
  new IntersectionObserver(([e], o) => {
    if (e.isIntersecting && !viewed) { viewed = true; track("product_viewed", { colour, source: "home" }); o.disconnect(); }
    if (e.isIntersecting) COLOURS.forEach(([k]) => { new Image().src = `assets/gallery/${k}/1.webp`; });
  }, { threshold: 0.35 }).observe($("#colours"));
}

/* ---------- colour strip + final row ---------- */
function buildStrips() {
  $("[data-strip]").innerHTML = COLOURS.map(([k, n]) =>
    `<a class="chip" href="#colours" data-pick="${k}" data-cta="strip_${k}">
       <img src="assets/gallery/${k}/1-sm.webp" alt="" width="240" height="150" loading="lazy"><span class="label">${n}</span></a>`).join("");
  $("[data-final-cams]").innerHTML = COLOURS.slice(0, 6).map(([k]) =>
    `<img src="assets/gallery/${k}/1-sm.webp" alt="" width="240" height="160" loading="lazy">`).join("");
  document.addEventListener("click", (e) => { const p = e.target.closest("[data-pick]"); if (p) setColour(p.dataset.pick, true); });
}

/* ---------- links ---------- */
function wireLinks() {
  const c = CFG.contact || {};
  $$("[data-instagram]").forEach((a) => { a.href = c.instagram || "#"; a.rel = "noopener"; });
  $$("[data-contact]").forEach((a) => { a.href = c.whatsapp || "#"; a.rel = "noopener"; });
  $$("[data-email]").forEach((a) => (a.href = c.email || "#"));
}

/* ---------- looks ---------- */
function wireLooks() {
  const stage = $("[data-look-stage]"), label = $("[data-look-name]");
  $$("[data-look]").forEach((b) => b.addEventListener("click", () => {
    const k = b.dataset.look, n = $(".label", b).textContent;
    $$("[data-look]").forEach((x) => x.setAttribute("aria-pressed", x === b));
    const next = new Image(); next.src = `assets/looks/look_${k}.webp`;
    stage.style.opacity = .35;
    next.decode().catch(() => {}).finally(() => { stage.src = next.src; stage.alt = `Two friends at a bar, ${n} look`; stage.style.opacity = 1; });
    label.textContent = n;
    track("look_selected", { look: k });
  }));
}

/* ---------- photo wall ---------- */
function buildWall() {
  const fig = ([n, cap], hidden) =>
    `<figure class="shot"${hidden ? ' aria-hidden="true"' : ""}><div class="ph">
      <img src="assets/photos/${n}-sm.webp" alt="${hidden ? "" : cap}" width="640" height="360" loading="lazy"></div>
      <figcaption class="label">${cap}</figcaption></figure>`;
  const rows = [PHOTOS.filter((_, i) => i % 2 === 0), PHOTOS.filter((_, i) => i % 2 === 1)];
  $("[data-wall]").innerHTML = rows.map((r, i) =>
    `<div class="wall-track${i ? " rev" : ""}" style="--dur:${i ? 95 : 80}s">${r.map((p) => fig(p)).join("")}${r.map((p) => fig(p, true)).join("")}</div>`).join("");
}

/* ---------- app use cases + template strip ---------- */
const TEMPLATES = ["J3", "LD1", "TR6", "M4", "B5", "J6", "LD5", "M7", "S7", "TR4", "B2", "M12"];
function wireUses() {
  const screen = $("[data-use-screen]");
  const tabs = $$("[data-use]");
  const select = (b, focus) => {
    tabs.forEach((x) => { x.setAttribute("aria-selected", x === b); x.tabIndex = x === b ? 0 : -1; });
    screen.style.opacity = 0;
    const next = new Image(); next.src = `assets/templates/${b.dataset.use}.webp`;
    next.decode().catch(() => {}).finally(() => { screen.src = next.src; screen.alt = `Glimp app: ${$(".t", b).textContent}`; screen.style.opacity = 1; });
    if (focus) b.focus();
    track("app_usecase_selected", { usecase: b.dataset.use });
  };
  tabs.forEach((b, i) => {
    b.tabIndex = i ? -1 : 0;
    b.addEventListener("click", () => select(b));
    b.addEventListener("keydown", (e) => {
      const d = { ArrowDown: 1, ArrowRight: 1, ArrowUp: -1, ArrowLeft: -1 }[e.key];
      if (d) { e.preventDefault(); select(tabs[(i + d + tabs.length) % tabs.length], true); }
    });
  });
  const tile = (c, hidden) => `<img src="assets/templates/${c}-sm.webp" alt="${hidden ? "" : "Glimp app template"}" width="300" height="534" loading="lazy"${hidden ? ' aria-hidden="true"' : ""}>`;
  $("[data-templates]").innerHTML = TEMPLATES.map((c) => tile(c)).join("") + TEMPLATES.map((c) => tile(c, true)).join("");
}

/* ---------- seven-segment date stamp (like a film camera's imprint), today in IST ---------- */
const SEG = {
  a: "1,0 9,0 7.6,2 2.4,2", b: "10,0.8 10,8.6 8,7.6 8,2.4", c: "10,9.4 10,17.2 8,15.6 8,10.4",
  d: "2.4,16 7.6,16 9,18 1,18", e: "0,9.4 2,10.4 2,15.6 0,17.2", f: "0,0.8 2,2.4 2,7.6 0,8.6",
  g: "1.2,9 2.4,8 7.6,8 8.8,9 7.6,10 2.4,10",
};
const DIGIT = ["abcdef", "bc", "abged", "abgcd", "fgbc", "afgcd", "afgedc", "abc", "abcdefg", "abfgcd"];
function stampSvg(text) {
  let x = 0, out = "";
  for (const ch of text) {
    if (/\d/.test(ch)) {
      out += `<g transform="translate(${x} 0)">${[...DIGIT[ch]].map((s) => `<polygon points="${SEG[s]}"/>`).join("")}</g>`;
      x += 13;
    } else if (ch === "'") { out += `<polygon points="${x + 1},0 ${x + 3.4},0 ${x + 2},5 ${x},5"/>`; x += 6; }
    else if (ch === ":") { out += `<rect x="${x + 1}" y="4" width="2.2" height="2.2"/><rect x="${x + 1}" y="11.5" width="2.2" height="2.2"/>`; x += 6; }
    else x += 8;                                                     // space
  }
  return `<svg viewBox="-2 -1 ${x + 4} 20" fill="#fff"><g transform="skewX(-10)">${out}</g></svg>`;
}
function wireStamp() {
  const el = $("[data-stamp]"); if (!el) return;
  const draw = () => {
    const ist = new Date(Date.now() + 5.5 * 3600e3).toISOString();       // yyyy-mm-ddThh:mm
    el.innerHTML = stampSvg(`'${ist.slice(2, 4)} ${ist.slice(5, 7)} ${ist.slice(8, 10)}  ${ist.slice(11, 16)}`);
  };
  draw(); setInterval(draw, 30000);
}

/* ---------- FAQ ---------- */
function wireFaq() {
  $$("[data-faq]").forEach((d) => d.addEventListener("toggle", () => { if (d.open) track("faq_opened", { faq_id: d.dataset.faq }); }));
}

/* ---------- sticky buy bar ---------- */
function wireBuyBar() {
  const bar = $("[data-buybar]");
  let heroGone = false, shopIn = false;
  const update = () => {
    const show = heroGone && !shopIn;
    bar.classList.toggle("show", show); bar.setAttribute("aria-hidden", !show);
    $("a", bar).tabIndex = show ? 0 : -1;
  };
  new IntersectionObserver(([e]) => { heroGone = !e.isIntersecting; update(); }).observe($(".hero"));
  new IntersectionObserver(([e]) => { shopIn = e.isIntersecting; update(); }, { threshold: 0.2 }).observe($("#colours"));
}

/* ---------- gentle settle-in ---------- */
function wireSettle() {
  const io = new IntersectionObserver((es) => es.forEach((e) => {
    if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
  }), { rootMargin: "0px 0px -10% 0px" });
  $$(".settle").forEach((el, i) => { el.style.transitionDelay = `${(i % 4) * 70}ms`; io.observe(el); });
}

/* ---------- theme ---------- */
function wireTheme() {
  const root = document.documentElement;
  let cur = "auto";
  try { cur = localStorage.getItem("glimp-theme") || "auto"; } catch (e) {}
  const apply = (t) => {
    if (t === "auto") delete root.dataset.theme; else root.dataset.theme = t;
    $$("[data-theme-set]").forEach((b) => b.setAttribute("aria-pressed", b.dataset.themeSet === t));
    try { t === "auto" ? localStorage.removeItem("glimp-theme") : localStorage.setItem("glimp-theme", t); } catch (e) {}
  };
  $$("[data-theme-set]").forEach((b) => b.addEventListener("click", () => apply(b.dataset.themeSet)));
  apply(cur);
}

/* ---------- phone input helper ---------- */
function phoneInput(el) {
  el.addEventListener("input", () => {
    let d = el.value.replace(/\D/g, ""); if (d.length > 10 && d.startsWith("91")) d = d.slice(2);
    d = d.slice(0, 10); el.value = d.length > 5 ? d.slice(0, 5) + " " + d.slice(5) : d;
  });
}
const validPhone = (v) => /^[6-9]\d{9}$/.test(v.replace(/\D/g, ""));

/* ---------- order form ---------- */
function wireOrder() {
  const dlg = $("[data-order]"), form = $("[data-order-form]"), done = $("[data-order-done]");
  const msg = $("[data-order-msg]"), submit = $("[data-order-submit]"), qty = form.elements.qty;
  const colourSel = form.elements.colour, img = $("[data-order-img]");
  let checkoutId = null, touched = null, placed = false;

  const sync = () => {
    $("[data-order-total]").textContent = inr(PRICE * +qty.value);
    img.src = `assets/gallery/${colourSel.value}/1-sm.webp`;
  };
  const open = (c) => {
    colourSel.value = c;
    form.hidden = false; done.hidden = true; msg.hidden = true;
    checkoutId = crypto.randomUUID ? crypto.randomUUID() : String(Date.now());
    touched = null; placed = false;
    sync();
    if (dlg.showModal) dlg.showModal(); else dlg.setAttribute("open", "");
    setTimeout(() => form.elements.name.focus(), 50);
    track("checkout_started", { checkout_id: checkoutId, colour: c, qty: +qty.value, value_paise: PRICE * 100 * +qty.value });
  };
  const close = () => {
    if (!placed && touched) track("form_abandoned", { form_id: "order", last_field: touched, checkout_id: checkoutId });
    touched = null;
    dlg.close ? dlg.close() : dlg.removeAttribute("open");
  };

  $("[data-buy-selected]").addEventListener("click", () => (stockOf(colour) === "out" ? openRestock(colour) : open(colour)));
  $$("[data-order-close]", dlg).forEach((b) => b.addEventListener("click", close));
  dlg.addEventListener("click", (e) => { if (e.target === dlg) close(); });
  dlg.addEventListener("cancel", (e) => { e.preventDefault(); close(); });
  colourSel.addEventListener("change", sync);
  $$("[data-qty]", form).forEach((b) => b.addEventListener("click", () => {
    qty.value = Math.max(1, Math.min(5, +qty.value + +b.dataset.qty)); sync();
  }));
  form.addEventListener("input", (e) => { if (e.target.name && e.target.name !== "website") touched = e.target.name; });

  const pin = form.elements.pincode;
  pin.addEventListener("input", () => { pin.value = pin.value.replace(/\D/g, "").slice(0, 6); });
  phoneInput(form.elements.phone);

  const rules = {
    name: (v) => v.trim().length >= 2,
    phone: validPhone,
    address: (v) => v.trim().length >= 8,
    pincode: (v) => /^[1-9]\d{5}$/.test(v),
    city: (v) => v.trim().length >= 2,
    state: (v) => !!v,
  };
  const check = (name, report) => {
    const el = form.elements[name], ok = rules[name](el.value);
    el.closest(".field").classList.toggle("bad", !ok); el.setAttribute("aria-invalid", !ok);
    if (!ok && report) track("checkout_field_error", { checkout_id: checkoutId, field: name, error_type: el.value.trim() ? "invalid_format" : "empty" });
    return ok;
  };
  Object.keys(rules).forEach((n) => form.elements[n].addEventListener("blur", () => { if (form.elements[n].value) check(n, true); }));

  const ERR = {
    sold_out: () => `${nameOf(colourSel.value)} just sold out. Pick another colour.`,
    limit: () => "That’s a lot of orders from one number today. Message us on WhatsApp.",
    colour: () => "Pick a colour.",
  };
  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    msg.hidden = true;
    const bad = Object.keys(rules).filter((n) => !check(n, true));
    if (bad.length) { form.elements[bad[0]].focus(); return; }
    const f = Object.fromEntries(new FormData(form));
    const s = window.glimp?.session() || {};
    const payload = { ...f, phone: f.phone.replace(/\D/g, ""), qty: +f.qty, session_id: s.session_id, anonymous_id: s.anonymous_id,
                      attr: s.attr, device_type: s.device_type, internal: s.internal };
    submit.disabled = true; submit.firstChild.textContent = "Placing order… ";
    try {
      const out = await rpc("place_order", { p: payload });
      if (!out.ok) {
        if (rules[out.error]) { check(out.error, true); form.elements[out.error].focus(); return; }
        msg.textContent = (ERR[out.error] || (() => "Something went wrong. Try again, or message us on WhatsApp."))();
        msg.hidden = false;
        if (out.error === "sold_out") loadStock();
        return;
      }
      placed = true;
      track("order_placed", { checkout_id: checkoutId, order_no: out.order, colour: f.colour, qty: +f.qty,
                              value_paise: PRICE * 100 * +f.qty, payment_method: "cod" }, { now: true });
      $("[data-order-id]").textContent = out.order;
      form.hidden = true; done.hidden = false; form.reset(); qty.value = 1;
      $("button", done).focus();
      loadStock();
    } catch (err) {
      msg.textContent = "That didn’t go through. The internet can be like that. Try once more, or message us on WhatsApp.";
      msg.hidden = false;
    } finally {
      submit.disabled = false; submit.firstChild.textContent = "Place order ";
    }
  });

  // glimp.in/#order or #order-teal opens the form directly (for the Instagram bio and ads)
  const fromHash = () => {
    const m = location.hash.match(/^#order(?:-([a-z]+))?$/);
    if (!m) return;
    const c = COLOURS.some(([k]) => k === m[1]) ? m[1] : colour;
    setColour(c, true);
    $("#colours").scrollIntoView();
    stockOf(c) === "out" ? openRestock(c) : open(c);
  };
  window.addEventListener("hashchange", fromHash);
  setTimeout(fromHash, 0);
}

/* ---------- sold out: notify me ---------- */
let openRestock = () => {};
function wireRestock() {
  const dlg = $("[data-restock]"), form = $("[data-restock-form]"), msg = $("[data-restock-msg]");
  let which = null;
  phoneInput(form.elements.phone);
  openRestock = (c) => {
    which = c; msg.hidden = true; form.reset();
    $("[data-restock-colour]").textContent = `${nameOf(c)} · sold out`;
    dlg.showModal ? dlg.showModal() : dlg.setAttribute("open", "");
  };
  $("[data-restock-close]").addEventListener("click", () => dlg.close());
  dlg.addEventListener("click", (e) => { if (e.target === dlg) dlg.close(); });
  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    const field = form.elements.phone.closest(".field");
    if (!validPhone(form.elements.phone.value)) { field.classList.add("bad"); return; }
    field.classList.remove("bad");
    try {
      const out = await rpc("notify_restock", { p_colour: which, p_phone: form.elements.phone.value.replace(/\D/g, ""),
                                                p_session: window.glimp?.session().session_id || null });
      msg.textContent = out.ok ? "Done. We’ll message you when it’s back." : "Check the number and try again.";
      if (out.ok) track("notify_me_requested", { colour: which });
    } catch { msg.textContent = "That didn’t go through. Try again in a bit."; }
    msg.hidden = false;
  });
}

wireShop(); buildStrips(); wireLinks(); wireLooks(); buildWall(); wireUses(); wireFaq();
wireBuyBar(); wireSettle(); wireTheme(); wireRestock(); wireOrder(); wireStamp(); loadStock();
