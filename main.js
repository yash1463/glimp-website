/* Glimp site behaviour. No libraries.
   ─────────────────────────────────────────────────────────────
   EDIT HERE when the store goes live: every buy link on the page reads from STORE. */
const STORE = {
  base: "https://YOUR-STORE.myshopify.com",       // or your own domain once Shopify is connected
  cart: "/cart",
  // Shopify product handle for each colour (Admin → Products → the product → URL handle)
  products: {
    black: "glimp-black", white: "glimp-white", red: "glimp-red", yellow: "glimp-yellow",
    blue: "glimp-blue", lime: "glimp-lime", teal: "glimp-teal", grey: "glimp-grey",
  },
  instagram: "https://instagram.com/",            // TODO: your handle
  whatsapp: "https://wa.me/91XXXXXXXXXX",          // TODO: your number
  email: "mailto:hello@example.com",              // TODO: your address
};
const LIVE = !STORE.base.includes("YOUR-STORE");   // until then, buy buttons scroll to the colour picker

const COLOURS = [
  ["black", "Black"], ["white", "White"], ["red", "Red"], ["yellow", "Yellow"],
  ["blue", "Blue"], ["lime", "Lime"], ["teal", "Teal"], ["grey", "Grey"],
];

/* Sample photos for the wall: [file, caption, date] (the date is burned into each photo already). Swap these for real Glimp shots: put files in assets/photos and edit this list. */
const PHOTOS = [
  ["01", "Monsoon walk", "’26 10 02"], ["02", "Tea stall", "’26 10 04"], ["03", "Auto, 9am", "’26 10 06"], ["04", "Local train", "’26 10 08"], ["05", "Chai + rusk", "’26 10 09"],
  ["06", "Building dog", "’26 10 12"], ["07", "Beach shacks", "’26 10 16"], ["08", "Low tide", "’26 10 16"], ["09", "Church by the sea", "’26 10 17"], ["10", "Shack lights", "’26 10 17"],
  ["11", "Thali", "’26 10 18"], ["12", "Two cuttings", "’26 10 23"], ["13", "Sea face", "’26 10 24"], ["14", "New café", "’26 10 26"], ["15", "Old city", "’26 10 28"],
  ["16", "Rangoli", "’26 10 29"], ["17", "Diyas", "’26 10 29"],
];

const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const productUrl = (c) => `${STORE.base}/products/${STORE.products[c]}`;

/* ---------- colour picker ---------- */
let colour = "black";
function setColour(c, focus) {
  colour = c;
  const name = COLOURS.find(([k]) => k === c)[1];
  const img = $("[data-shop-img]");
  img.style.opacity = 0;
  const next = new Image();
  next.src = `assets/cam/${c}.webp`;
  next.decode().catch(() => {}).finally(() => {
    img.src = next.src; img.alt = `Glimp camera in ${name}`; img.style.opacity = 1;
  });
  $("[data-colour-name]").textContent = name;
  const buy = $("[data-buy-selected]");
  buy.firstChild.textContent = `Pre-order ${name} — ₹1,490 `;
  buy.href = LIVE ? productUrl(c) : "#colours";
  $$("[data-swatch]").forEach((b) => {
    const on = b.dataset.swatch === c;
    b.setAttribute("aria-checked", on); b.tabIndex = on ? 0 : -1;
    if (on && focus) b.focus();
  });
}
function buildSwatches() {
  const wrap = $("[data-swatches]");
  wrap.innerHTML = COLOURS.map(([k, n]) =>
    `<button class="swatch" role="radio" aria-checked="false" aria-label="${n}" title="${n}" data-swatch="${k}">
       <img src="assets/cam/${k}-sm.webp" alt="" width="320" height="185" loading="lazy"></button>`).join("");
  wrap.addEventListener("click", (e) => { const b = e.target.closest("[data-swatch]"); if (b) setColour(b.dataset.swatch); });
  wrap.addEventListener("keydown", (e) => {
    const keys = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 };
    if (!(e.key in keys)) return;
    e.preventDefault();
    const i = COLOURS.findIndex(([k]) => k === colour);
    setColour(COLOURS[(i + keys[e.key] + COLOURS.length) % COLOURS.length][0], true);
  });
  // preload the big images once the picker is near
  new IntersectionObserver((es, o) => { if (es[0].isIntersecting) { COLOURS.forEach(([k]) => { new Image().src = `assets/cam/${k}.webp`; }); o.disconnect(); } },
    { rootMargin: "400px" }).observe(wrap);
  setColour("black");
}

/* ---------- links ---------- */
function wireLinks() {
  if (LIVE) {
    $$("[data-cart]").forEach((a) => (a.href = STORE.base + STORE.cart));
  }
  $$("[data-instagram]").forEach((a) => (a.href = STORE.instagram));
  $$("[data-contact]").forEach((a) => (a.href = STORE.whatsapp));
  $$("[data-email]").forEach((a) => (a.href = STORE.email));
  $$("[data-policy]").forEach((a) => (a.href = LIVE ? `${STORE.base}/policies/${a.dataset.policy}-policy` : "#faq"));
}

/* ---------- looks ---------- */
function wireLooks() {
  const stage = $("[data-look-stage]"), label = $("[data-look-name]");
  $$("[data-look]").forEach((b) => b.addEventListener("click", () => {
    const k = b.dataset.look, n = $(".label", b).textContent;
    $$("[data-look]").forEach((x) => x.setAttribute("aria-pressed", x === b));
    const next = new Image(); next.src = `assets/looks/${k}.webp`;
    stage.style.opacity = .35;
    next.decode().catch(() => {}).finally(() => {
      stage.src = next.src; stage.alt = `Three friends on a bridge, shown in the ${n} look`; stage.style.opacity = 1;
    });
    label.textContent = n;
  }));
}

/* ---------- photo wall ---------- */
function buildWall() {
  const wall = $("[data-wall]");
  const fig = ([n, cap], hidden) => {
    return `<figure class="shot"${hidden ? ' aria-hidden="true"' : ""}><div class="ph">
      <img src="assets/photos/${n}-sm.webp" alt="${hidden ? "" : cap}" width="640" height="360" loading="lazy"></div>
      <figcaption class="label">${cap}</figcaption></figure>`;
  };
  const rows = [PHOTOS.filter((_, i) => i % 2 === 0), PHOTOS.filter((_, i) => i % 2 === 1)];
  wall.innerHTML = rows.map((r, i) =>
    `<div class="wall-track${i ? " rev" : ""}" style="--dur:${i ? 95 : 80}s">${r.map((p) => fig(p)).join("")}${r.map((p) => fig(p, true)).join("")}</div>`).join("");
}

/* ---------- app use cases ---------- */
function wireUses() {
  const screen = $("[data-use-screen]"), lab = $("[data-app-label]");
  const labels = { journal_three_note: "Today", us_distance: "Riya", baby_firstYear: "Aarav", trip_stamps: "Goa", collage_polaroids: "Make" };
  const tabs = $$("[data-use]");
  const select = (b, focus) => {
    tabs.forEach((x) => { x.setAttribute("aria-selected", x === b); x.tabIndex = x === b ? 0 : -1; });
    screen.style.opacity = 0;
    const next = new Image(); next.src = `assets/app/${b.dataset.use}.webp`;
    next.decode().catch(() => {}).finally(() => { screen.src = next.src; screen.alt = `KeyCam app: ${$(".t", b).textContent}`; screen.style.opacity = 1; });
    lab.textContent = labels[b.dataset.use] || "";
    if (focus) b.focus();
  };
  tabs.forEach((b, i) => {
    b.tabIndex = i ? -1 : 0;
    b.addEventListener("click", () => select(b));
    b.addEventListener("keydown", (e) => {
      const d = { ArrowDown: 1, ArrowRight: 1, ArrowUp: -1, ArrowLeft: -1 }[e.key];
      if (d) { e.preventDefault(); select(tabs[(i + d + tabs.length) % tabs.length], true); }
    });
  });
}

/* ---------- compare table ---------- */
function wireCompare() {
  const t = $(".compare-toggle"), box = $("#compare");
  t.addEventListener("click", () => {
    const open = box.hidden; box.hidden = !open;
    t.setAttribute("aria-expanded", open);
    t.textContent = open ? "Hide the side-by-side ‹" : "See the side-by-side ›";
  });
}

/* ---------- final row of cameras ---------- */
function buildFinal() {
  $("[data-final-cams]").innerHTML = COLOURS.slice(0, 6).map(([k]) =>
    `<img src="assets/cam/${k}-sm.webp" alt="" width="320" height="185" loading="lazy">`).join("");
}

/* ---------- buy buttons ---------- */
function wireBuy() {
  $$("[data-buy]").forEach((a) => { a.href = "#colours"; });
  const bar = $("[data-buybar]"), hero = $(".hero"), shop = $("#colours");
  let heroGone = false, shopIn = false;
  const update = () => {
    const show = heroGone && !shopIn;
    bar.classList.toggle("show", show); bar.setAttribute("aria-hidden", !show);
    $("a", bar).tabIndex = show ? 0 : -1;
  };
  new IntersectionObserver(([e]) => { heroGone = !e.isIntersecting; update(); }).observe(hero);
  new IntersectionObserver(([e]) => { shopIn = e.isIntersecting; update(); }, { threshold: 0.2 }).observe(shop);
}

/* ---------- gentle settle-in for cards ---------- */
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

buildSwatches(); wireLinks(); wireLooks(); buildWall(); wireUses(); wireCompare(); buildFinal(); wireBuy(); wireSettle(); wireTheme();
