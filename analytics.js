/* glimp.in analytics — browser side. No libraries.
   Contract: glimp-analytics-spec/03-event-taxonomy.md. Storage rules: file 02. Consent: file 09.

   Before consent: no analytics cookies. Only essential events (page_viewed, product_viewed, checkout_started,
   order_placed, consent_updated), with a tab-only session id (sessionStorage) and anonymous_id = null.
   After "analytics" consent: glimp_vid (12 months) + rolling 30-min glimp_sid + first-touch glimp_ft,
   full behaviour events, and Microsoft Clarity. "marketing" consent adds the Meta Pixel. */
(() => {
  const CFG = window.GLIMP_CONFIG || {};
  const ENDPOINT = CFG.supabaseUrl ? `${CFG.supabaseUrl}/rest/v1/rpc/ingest` : "";
  const BANNER_VERSION = "1";
  const ESSENTIAL = ["page_viewed", "product_viewed", "checkout_started", "order_placed", "consent_updated"];
  const SESSION_MS = 30 * 60 * 1000;

  /* ---------- small helpers ---------- */
  const uuid = () => (crypto.randomUUID ? crypto.randomUUID() :
    "10000000-1000-4000-8000-100000000000".replace(/[018]/g, (c) =>
      (c ^ (crypto.getRandomValues(new Uint8Array(1))[0] & (15 >> (c / 4)))).toString(16)));
  const getCookie = (k) => document.cookie.split("; ").find((c) => c.startsWith(k + "="))?.split("=").slice(1).join("=");
  const setCookie = (k, v, days) => {
    document.cookie = `${k}=${v}; Max-Age=${Math.round(days * 86400)}; Path=/; SameSite=Lax${location.protocol === "https:" ? "; Secure" : ""}`;
  };
  const delCookie = (k) => { document.cookie = `${k}=; Max-Age=0; Path=/`; };
  const jget = (s) => { try { return JSON.parse(decodeURIComponent(s)); } catch { return null; } };
  const jset = (o) => encodeURIComponent(JSON.stringify(o));
  const ss = { get: (k) => { try { return sessionStorage.getItem(k); } catch { return null; } },
               set: (k, v) => { try { sessionStorage.setItem(k, v); } catch {} } };

  /* ---------- consent ---------- */
  let consent = jget(getCookie("glimp_consent") || "") || null;     // {v, analytics, marketing, ts}
  const consentState = () => !consent || (!consent.analytics && !consent.marketing) ? "none"
    : consent.analytics && consent.marketing ? "analytics+marketing" : consent.analytics ? "analytics" : "marketing";
  const full = () => !!consent?.analytics;

  /* ---------- internal traffic + bots ---------- */
  const qs = new URLSearchParams(location.search);
  if (qs.has("glimp_internal")) setCookie("glimp_int", qs.get("glimp_internal") === "0" ? "" : "1", qs.get("glimp_internal") === "0" ? 0 : 365);
  const isInternal = getCookie("glimp_int") === "1";
  const isBot = !!navigator.webdriver || /bot|crawl|spider|headless|lighthouse/i.test(navigator.userAgent);

  /* ---------- attribution (file 02 §4) ---------- */
  function landingAttr() {
    const a = {};
    ["utm_source", "utm_medium", "utm_campaign", "utm_content", "utm_term", "ref"].forEach((k) => {
      const v = qs.get(k); if (v) a[k] = v.slice(0, 100);
    });
    if (qs.has("fbclid")) a.fbclid = true;
    if (qs.has("gclid")) a.gclid = true;
    try {
      const r = document.referrer && new URL(document.referrer).hostname;
      if (r && r !== location.hostname) a.referrer_domain = r.replace(/^www\./, "");
    } catch {}
    a.landing_path = location.pathname;
    return a;
  }
  const attr = landingAttr();
  const newCampaign = !!(attr.utm_campaign || attr.fbclid || attr.gclid);

  /* ---------- identity ---------- */
  let anonId = null, session, carryId = null;   // carryId: keep the same visit id when consent arrives mid-visit
  function loadSession() {
    const now = Date.now();
    if (full()) {
      anonId = getCookie("glimp_vid") || uuid();
      setCookie("glimp_vid", anonId, 365);
      let s = jget(getCookie("glimp_sid") || "");
      const campaignKey = attr.utm_campaign || (attr.fbclid ? "fbclid" : "") || "";
      if (!s || now - s.last > SESSION_MS || (newCampaign && s.ck !== campaignKey + qs.get("fbclid"))) {
        s = { id: carryId || uuid(), start: now, last: now, seq: carryId ? session.seq : 0, ck: campaignKey + qs.get("fbclid"), fresh: !carryId };
      }
      if (!getCookie("glimp_ft") && Object.keys(attr).length > 1) setCookie("glimp_ft", jset({ ...attr, ts: now }), 90);
      session = s;
    } else {
      anonId = null;
      let id = ss.get("glimp_tab_sid");
      const fresh = !id;
      if (!id) { id = "t-" + uuid(); ss.set("glimp_tab_sid", id); }
      session = { id, seq: Number(ss.get("glimp_tab_seq") || 0), fresh };
    }
  }
  function saveSession() {
    session.last = Date.now();
    if (full()) setCookie("glimp_sid", jset({ ...session, fresh: false }), 1 / 48);
    else ss.set("glimp_tab_seq", String(session.seq));
  }
  loadSession();

  /* ---------- context (file 02 §5) ---------- */
  const ua = navigator.userAgent;
  const ctx = {
    device_type: /iPad|Tablet/i.test(ua) || (innerWidth >= 700 && innerWidth < 1024 && "ontouchstart" in window) ? "tablet"
      : /Mobi|Android|iPhone/i.test(ua) ? "mobile" : "desktop",
    os: /Android/i.test(ua) ? "Android" : /iPhone|iPad|iOS/i.test(ua) ? "iOS" : /Windows/i.test(ua) ? "Windows"
      : /Mac OS/i.test(ua) ? "macOS" : /Linux/i.test(ua) ? "Linux" : "other",
    browser: /FBAN|FBAV|Instagram/i.test(ua) ? "in-app" : /Edg\//.test(ua) ? "Edge" : /SamsungBrowser/.test(ua) ? "Samsung"
      : /Chrome\//.test(ua) ? "Chrome" : /Firefox\//.test(ua) ? "Firefox" : /Safari\//.test(ua) ? "Safari" : "other",
    connection_type: navigator.connection?.effectiveType || null,
    viewport_w: innerWidth,
  };

  /* ---------- queue ---------- */
  let queue = [];
  let timer = null;
  function send(batch, keepalive) {
    if (!ENDPOINT || !batch.length) return;
    if (CFG.debug) console.table(batch.map((e) => ({ event: e.event_name, ...e.props })));
    fetch(ENDPOINT, {
      method: "POST", keepalive,
      headers: { "Content-Type": "application/json", apikey: CFG.supabaseKey },
      body: JSON.stringify({ batch }),
    }).catch(() => {});
  }
  function flush(keepalive = false) {
    clearTimeout(timer); timer = null;
    while (queue.length) send(queue.splice(0, 20), keepalive);
  }
  function track(name, props = {}, opts = {}) {
    if (!full() && !ESSENTIAL.includes(name)) return null;
    session.seq += 1;
    const e = {
      event_id: opts.event_id || uuid(), event_name: name, client_ts: new Date().toISOString(),
      anonymous_id: anonId, session_id: session.id, seq: session.seq, consent_state: consentState(),
      page_path: location.pathname, ...ctx, props, site_version: CFG.version || null,
      is_bot: isBot, is_internal: isInternal,
    };
    if (opts.attr) e.attr = opts.attr;
    saveSession();
    queue.push(e);
    if (opts.now || queue.length >= 10) flush(opts.keepalive);
    else if (!timer) timer = setTimeout(flush, 4000);
    pixel(name, props, e.event_id);
    return e.event_id;
  }

  /* ---------- Meta Pixel (marketing consent only) ---------- */
  const PIXEL_MAP = { product_viewed: "ViewContent", checkout_started: "InitiateCheckout", order_placed: "Purchase" };
  let pixelOn = false;
  function loadPixel() {
    if (pixelOn || !CFG.metaPixelId || !consent?.marketing) return;
    pixelOn = true;
    /* eslint-disable */
    !function(f,b,e,v,n,t,s){if(f.fbq)return;n=f.fbq=function(){n.callMethod?n.callMethod.apply(n,arguments):n.queue.push(arguments)};
    if(!f._fbq)f._fbq=n;n.push=n;n.loaded=!0;n.version='2.0';n.queue=[];t=b.createElement(e);t.async=!0;t.src=v;
    s=b.getElementsByTagName(e)[0];s.parentNode.insertBefore(t,s)}(window,document,'script','https://connect.facebook.net/en_US/fbevents.js');
    /* eslint-enable */
    fbq("init", CFG.metaPixelId);
    fbq("track", "PageView");          // fired here: page_viewed happens before consent/loading
  }
  function pixel(name, props, eventId) {
    if (!pixelOn || !PIXEL_MAP[name]) return;
    const data = { currency: "INR", content_type: "product" };
    if (props.colour) data.content_ids = ["glimp-" + props.colour];
    if (props.value_paise) data.value = props.value_paise / 100;
    fbq("track", PIXEL_MAP[name], data, { eventID: eventId });
  }

  /* ---------- Microsoft Clarity (analytics consent only) ---------- */
  let clarityOn = false;
  function loadClarity() {
    if (clarityOn || !CFG.clarityId || !consent?.analytics) return;
    clarityOn = true;
    /* eslint-disable */
    (function(c,l,a,r,i,t,y){c[a]=c[a]||function(){(c[a].q=c[a].q||[]).push(arguments)};
    t=l.createElement(r);t.async=1;t.src="https://www.clarity.ms/tag/"+i;y=l.getElementsByTagName(r)[0];y.parentNode.insertBefore(t,y);
    })(window, document, "clarity", "script", CFG.clarityId);
    /* eslint-enable */
    clarity("set", "glimp_session", session.id);
  }

  /* ---------- consent banner ---------- */
  function applyConsent(c, source) {
    const before = consentState();
    consent = { v: 1, analytics: !!c.analytics, marketing: !!c.marketing, ts: Date.now() };
    setCookie("glimp_consent", jset(consent), 365);
    if (!consent.analytics) ["glimp_vid", "glimp_sid", "glimp_ft"].forEach(delCookie);
    if (!consent.marketing) ["_fbp", "_fbc"].forEach(delCookie);
    if (before === "none" && session.id.startsWith("t-")) carryId = session.id;   // upgrade mid-visit: same session id
    loadSession();
    carryId = null;
    track("consent_updated", { analytics: consent.analytics, marketing: consent.marketing,
      banner_version: BANNER_VERSION, language: document.documentElement.lang || "en", from: before, via: source }, { now: true });
    if (full() && before === "none") startBehaviour();
    loadClarity(); loadPixel();
    if (!consent.analytics && clarityOn) location.reload();   // stop a running recorder right away
  }

  function banner(openChoose = false) {
    let el = document.querySelector("[data-consent]");
    if (!el) {
      el = document.createElement("div");
      el.className = "consent"; el.dataset.consent = "";
      el.setAttribute("role", "dialog"); el.setAttribute("aria-label", "Cookie choices");
      el.innerHTML = `
        <p class="consent-t">Cookies help us see what’s working on this page. Your call.</p>
        <p class="consent-hi" lang="hi">कुकीज़ से हमें पता चलता है कि पेज पर क्या काम कर रहा है। आपकी मर्ज़ी।</p>
        <div class="consent-choose" hidden>
          <label><input type="checkbox" checked disabled> <span>Necessary</span><small>Order form, this choice</small></label>
          <label><input type="checkbox" data-c="analytics"> <span>Analytics</span><small>Visits, scrolls, screen recordings with inputs hidden (Microsoft Clarity)</small></label>
          <label><input type="checkbox" data-c="marketing"> <span>Marketing</span><small>Meta Pixel, to measure our ads</small></label>
        </div>
        <div class="consent-b">
          <button type="button" data-a="all">Accept all</button>
          <button type="button" data-a="none">Reject all</button>
          <button type="button" data-a="choose">Choose</button>
        </div>
        <a class="consent-more" href="/privacy.html">Privacy</a>`;
      document.body.appendChild(el);
      const choose = el.querySelector(".consent-choose");
      el.addEventListener("click", (e) => {
        const a = e.target.closest("[data-a]")?.dataset.a;
        if (!a) return;
        if (a === "choose" && choose.hidden) {
          choose.hidden = false;
          el.querySelector('[data-a="choose"]').textContent = "Save";
          el.querySelector('[data-c="analytics"]').checked = !!consent?.analytics;
          el.querySelector('[data-c="marketing"]').checked = !!consent?.marketing;
          return;
        }
        const c = a === "all" ? { analytics: true, marketing: true } : a === "none" ? { analytics: false, marketing: false }
          : { analytics: el.querySelector('[data-c="analytics"]').checked, marketing: el.querySelector('[data-c="marketing"]').checked };
        applyConsent(c, a);
        el.remove();
      });
    }
    if (openChoose) el.querySelector('[data-a="choose"]').click();
  }
  document.addEventListener("click", (e) => {
    if (e.target.closest("[data-cookie-settings]")) { e.preventDefault(); banner(true); }
  });

  /* ---------- page + behaviour ---------- */
  const t0 = performance.now();
  let visibleMs = 0, visibleSince = document.visibilityState === "visible" ? performance.now() : null, maxScroll = 0, engagedSent = false;
  const engagedMs = () => visibleMs + (visibleSince ? performance.now() - visibleSince : 0);
  function engaged() { if (!engagedSent && full()) { engagedSent = true; track("page_engaged"); } }

  let behaviourStarted = false;
  function startBehaviour() {
    if (behaviourStarted || !full()) return;
    behaviourStarted = true;
    setTimeout(engaged, 10000);
    document.addEventListener("click", engaged, { once: true });

    // scroll depth
    const marks = [25, 50, 75, 90, 100]; const hit = new Set();
    const onScroll = () => {
      const h = document.documentElement.scrollHeight - innerHeight;
      const pct = h <= 0 ? 100 : Math.round((scrollY / h) * 100);
      maxScroll = Math.max(maxScroll, pct);
      if (pct >= 50) engaged();
      marks.forEach((m) => { if (pct >= m && !hit.has(m)) { hit.add(m); track("scroll_depth_reached", { depth_pct: m }); } });
    };
    addEventListener("scroll", onScroll, { passive: true });

    // sections: ≥50% visible for ≥1 s, once each
    const seen = new Set(), timers = new Map();
    const io = new IntersectionObserver((es) => es.forEach((en) => {
      const id = en.target.dataset.section;
      if (seen.has(id)) return;
      if (en.isIntersecting) timers.set(id, setTimeout(() => {
        seen.add(id); track("section_viewed", { section_id: id });
        if (id === "comparison") track("comparison_viewed");
      }, 1000));
      else clearTimeout(timers.get(id));
    }), { threshold: 0.5 });
    document.querySelectorAll("[data-section]").forEach((s) => {
      // tall sections can never be 50% visible on a phone: watch their heading instead
      const target = s.offsetHeight > innerHeight * 1.6 ? (s.querySelector("h1,h2") || s) : s;
      target.dataset.section = s.dataset.section; io.observe(target);
    });

    // clicks: CTAs, nav, outbound, rage
    let clicks = [];
    document.addEventListener("click", (e) => {
      const cta = e.target.closest("[data-cta]");
      if (cta) track("cta_clicked", { cta_id: cta.dataset.cta, section_id: cta.closest("[data-section]")?.dataset.section || null });
      const nav = e.target.closest("nav a, footer a");
      if (nav && !cta) track("nav_clicked", { nav_item: (nav.getAttribute("href") || "").slice(0, 40), location: nav.closest("footer") ? "footer" : "header" });
      const a = e.target.closest("a[href^='http']");
      if (a) {
        const host = new URL(a.href).hostname;
        if (/wa\.me|whatsapp/.test(host)) track("whatsapp_clicked", { location: a.closest("[data-section]")?.dataset.section || "page" });
        else if (/instagram/.test(host)) track("instagram_clicked", { url_domain: host });
        else if (host !== location.hostname) track("outbound_link_clicked", { url_domain: host });
      }
      const now = performance.now();
      clicks = clicks.filter((c) => now - c.t < 1000 && Math.hypot(c.x - e.clientX, c.y - e.clientY) < 30);
      clicks.push({ t: now, x: e.clientX, y: e.clientY });
      if (clicks.length === 3) {
        const el = e.target;
        track("rage_click", { selector: selectorOf(el), element_text: (el.textContent || "").trim().slice(0, 40),
          section_id: el.closest("[data-section]")?.dataset.section || null });
      }
    }, true);

    // errors (5 per page)
    let errs = 0;
    addEventListener("error", (e) => {
      if (errs++ < 5 && e.message) track("js_error", { message: String(e.message).slice(0, 200), source: (e.filename || "").split("/").pop(), line: e.lineno || null });
    });
    addEventListener("unhandledrejection", (e) => {
      if (errs++ < 5) track("js_error", { message: String(e.reason?.message || e.reason).slice(0, 200), source: "promise" });
    });

    vitals();
  }

  function selectorOf(el) {
    if (!el || el === document.body) return "body";
    if (el.id) return "#" + el.id;
    const c = [...el.classList].slice(0, 2).join(".");
    return (el.tagName.toLowerCase() + (c ? "." + c : "")).slice(0, 60);
  }

  // Core Web Vitals without a library: LCP, CLS, FCP, TTFB (INP needs the web-vitals lib; skipped for now)
  function vitals() {
    const v = {};
    try {
      new PerformanceObserver((l) => { const e = l.getEntries().at(-1); if (e) v.lcp_ms = Math.round(e.startTime); })
        .observe({ type: "largest-contentful-paint", buffered: true });
      let cls = 0;
      new PerformanceObserver((l) => { l.getEntries().forEach((e) => { if (!e.hadRecentInput) cls += e.value; }); v.cls = Math.round(cls * 1000) / 1000; })
        .observe({ type: "layout-shift", buffered: true });
      const fcp = performance.getEntriesByName("first-contentful-paint")[0]; if (fcp) v.fcp_ms = Math.round(fcp.startTime);
      const nav = performance.getEntriesByType("navigation")[0]; if (nav) v.ttfb_ms = Math.round(nav.responseStart);
    } catch {}
    let sent = false;
    const report = () => { if (!sent && Object.keys(v).length) { sent = true; track("web_vitals_reported", v); } };
    addEventListener("visibilitychange", () => { if (document.visibilityState === "hidden") report(); });
    setTimeout(report, 15000);
  }

  // page_left on hide (sent with keepalive so it survives closing the tab)
  addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") {
      if (visibleSince) { visibleMs += performance.now() - visibleSince; visibleSince = null; }
      if (full()) track("page_left", { engaged_ms: Math.round(engagedMs()), max_scroll_pct: maxScroll }, { now: true, keepalive: true });
      flush(true);
    } else {
      visibleSince = performance.now();
    }
  });

  /* ---------- public API for main.js ---------- */
  window.glimp = {
    track,
    session: () => ({ session_id: session.id, anonymous_id: anonId, attr: getAttrForOrder(), device_type: ctx.device_type, internal: isInternal }),
    consent: () => consent,
    openCookieSettings: () => banner(true),
  };
  function getAttrForOrder() {
    const ft = jget(getCookie("glimp_ft") || "");
    const a = Object.keys(attr).length > 1 ? attr : (ft || attr);
    const { ts, ...rest } = a || {};
    return rest;
  }

  /* ---------- go ---------- */
  track("page_viewed", { page_type: location.pathname === "/" || location.pathname.endsWith("index.html") ? "home" : "other" },
        { attr: session.fresh || newCampaign ? attr : undefined });
  if (!consent) setTimeout(() => banner(), 1200);
  startBehaviour(); loadClarity(); loadPixel();
})();
