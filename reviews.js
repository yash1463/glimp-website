/* Glimp reviews: show approved reviews, write a review (stars, text, up to 4 photos from camera or gallery).
   Uses $, $$, rpc, track, CFG, validPhone, phoneInput from main.js. Data: get_reviews() / submit_review() in
   backend/supabase.sql; photos go to the public Supabase Storage bucket "reviews". */
(() => {
  const PHOTO = (u, thumb) => `${CFG.supabaseUrl}/storage/v1/object/public/reviews/r/${u}${thumb ? "-t" : ""}.jpg`;
  const MAX_PHOTOS = 4;
  const esc = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const stars = (r, cls = "") => `<span class="stars ${cls}" style="--r:${r}" role="img" aria-label="${r} out of 5 stars"></span>`;
  const when = (d) => {
    const t = new Date(d + "T12:00:00"), now = new Date();
    return t.toLocaleDateString("en-IN", { day: "numeric", month: "short", ...(t.getFullYear() !== now.getFullYear() ? { year: "numeric" } : {}) });
  };
  const open = (d) => (d.showModal ? d.showModal() : d.setAttribute("open", ""));
  const shut = (d) => (d.close ? d.close() : d.removeAttribute("open"));

  let DATA = { count: 0, reviews: [] };
  let PHOTOS = [];            // every photo across reviews: [{u, review}]

  /* ---------- one review card ---------- */
  const card = (r, full) => `<article class="rv-card${full ? " full" : ""}">
      <div class="rv-top">${stars(r.rating)}<time datetime="${esc(r.date)}">${when(r.date)}</time></div>
      <p class="rv-text">${esc(r.body)}</p>
      ${full ? "" : `<button type="button" class="rv-more" hidden>More</button>`}
      ${r.photos.length ? `<div class="rv-pics">${r.photos.map((u) =>
        `<button type="button" class="rv-pic" data-rv-photo="${esc(u)}" aria-label="Photo from ${esc(r.name)}"><img src="${PHOTO(u, true)}" alt="" loading="lazy" width="120" height="120"></button>`).join("")}</div>` : ""}
      <div class="rv-who"><b>${esc(r.name)}</b>${r.verified ? `<span class="rv-ver">Verified buyer</span>` : ""}</div>
    </article>`;

  /* ---------- section on the page ---------- */
  function render() {
    const { count, avg, reviews } = DATA;
    const sec = $("#reviews");
    sec.hidden = !count;
    const mini = $("[data-rv-mini]");
    mini.hidden = !count;
    if (!count) return;
    const n = `${count} review${count > 1 ? "s" : ""}`;
    $("[data-rv-avg]").textContent = Number(avg).toFixed(1);
    $("[data-rv-stars]").style.setProperty("--r", avg);
    $("[data-rv-n]").textContent = n;
    $("[data-rv-mini-stars]").style.setProperty("--r", avg);
    $("[data-rv-mini-avg]").textContent = Number(avg).toFixed(1);
    $("[data-rv-mini-n]").textContent = `${n}`;

    PHOTOS = reviews.flatMap((r) => r.photos.map((u) => ({ u, r })));
    const strip = $("[data-rv-photos]");
    strip.hidden = !PHOTOS.length;
    strip.innerHTML = PHOTOS.slice(0, 24).map(({ u, r }) =>
      `<button type="button" class="rv-ph" role="listitem" data-rv-photo="${esc(u)}" aria-label="Photo from ${esc(r.name)}"><img src="${PHOTO(u, true)}" alt="" loading="lazy" width="120" height="120"></button>`).join("");

    const SHOWN = 8;
    $("[data-rv-track]").innerHTML = reviews.slice(0, SHOWN).map((r) => card(r)).join("");
    // "More" only on cards whose text is cut off
    requestAnimationFrame(() => $$("#reviews .rv-card").forEach((c) => {
      const t = $(".rv-text", c), b = $(".rv-more", c);
      if (b) b.hidden = t.scrollHeight <= t.clientHeight + 2;
    }));
    // desktop arrows: only when the cards don't all fit
    const track = $("[data-rv-track]"), nav = $("[data-rv-nav]");
    const navState = () => {
      nav.hidden = track.scrollWidth <= track.clientWidth + 4;
      const [prev, next] = $$("button", nav);
      prev.disabled = track.scrollLeft < 8; next.disabled = track.scrollLeft + track.clientWidth >= track.scrollWidth - 8;
    };
    requestAnimationFrame(navState);
    track.onscroll = navState; window.addEventListener("resize", navState);
    nav.onclick = (e) => { const b = e.target.closest("[data-rv-scroll]"); if (b) track.scrollBy({ left: +b.dataset.rvScroll * track.clientWidth * 0.9, behavior: "smooth" }); };
    const all = $("[data-rv-all-open]");
    all.hidden = count < 2;
    all.textContent = `All ${n} ›`;
  }

  async function load() {
    try { DATA = await rpc("get_reviews"); } catch { DATA = { count: 0, reviews: [] }; }
    DATA.reviews = DATA.reviews || [];
    render();
    if (location.hash === "#review") openForm();
  }

  /* ---------- photo viewer ---------- */
  const lb = $("[data-rv-lb]");
  let lbList = [], lbAt = 0;
  function showPhoto(i) {
    lbAt = (i + lbList.length) % lbList.length;
    const { u, r } = lbList[lbAt];
    const img = $("[data-rv-lb-img]");
    img.src = PHOTO(u, true);                       // thumbnail first (cached), then the full photo
    const big = new Image(); big.onload = () => { if (lbList[lbAt].u === u) img.src = big.src; }; big.src = PHOTO(u);
    img.alt = `Photo from ${r.name}`;
    $("[data-rv-lb-cap]").innerHTML = `<div class="rv-top">${stars(r.rating)}<b>${esc(r.name)}</b>${r.verified ? `<span class="rv-ver">Verified buyer</span>` : ""}</div><p>${esc(r.body)}</p>`;
    $$("[data-rv-lb-go]", lb).forEach((b) => (b.hidden = lbList.length < 2));
  }
  function openPhoto(u, scope) {
    lbList = scope || PHOTOS;
    const i = lbList.findIndex((p) => p.u === u);
    open(lb); showPhoto(Math.max(0, i));
    track("review_photo_viewed", {});
  }
  $$("[data-rv-lb-go]", lb).forEach((b) => b.addEventListener("click", () => showPhoto(lbAt + +b.dataset.rvLbGo)));
  $("[data-rv-lb-close]").addEventListener("click", () => shut(lb));
  lb.addEventListener("click", (e) => { if (e.target === lb || e.target.classList.contains("rv-lb-stage")) shut(lb); });
  lb.addEventListener("keydown", (e) => { if (e.key === "ArrowRight") showPhoto(lbAt + 1); if (e.key === "ArrowLeft") showPhoto(lbAt - 1); });
  let x0 = null;
  lb.addEventListener("pointerdown", (e) => { x0 = e.clientX; });
  lb.addEventListener("pointerup", (e) => { if (x0 !== null && Math.abs(e.clientX - x0) > 40 && lbList.length > 1) showPhoto(lbAt + (e.clientX < x0 ? 1 : -1)); x0 = null; });

  document.addEventListener("click", (e) => {
    const ph = e.target.closest("[data-rv-photo]");
    if (ph) {
      // inside a card: page through that review's photos; from the strip: through all of them
      const inCard = ph.closest(".rv-card");
      const r = inCard && DATA.reviews.find((x) => x.photos.includes(ph.dataset.rvPhoto));
      return openPhoto(ph.dataset.rvPhoto, r ? r.photos.map((u) => ({ u, r })) : null);
    }
    const more = e.target.closest(".rv-more");
    if (more) { more.closest(".rv-card").classList.add("open"); more.hidden = true; }
  });

  /* ---------- all reviews ---------- */
  const allDlg = $("[data-rv-all]");
  let filter = "all", page = 0;
  const PAGE = 10;
  function filtered() {
    const list = DATA.reviews;
    if (filter === "photos") return list.filter((r) => r.photos.length);
    if (/^[1-5]$/.test(filter)) return list.filter((r) => r.rating === +filter);
    return [...list].sort((a, b) => (a.date < b.date ? 1 : -1));     // newest first
  }
  function renderAll() {
    const list = filtered();
    $("[data-rv-list]").innerHTML = list.slice(0, (page + 1) * PAGE).map((r) => card(r, true)).join("") || `<p class="rv-none">None yet.</p>`;
    $("[data-rv-more]").hidden = list.length <= (page + 1) * PAGE;
    $$("[data-rv-f]", allDlg).forEach((b) => b.setAttribute("aria-pressed", b.dataset.rvF === filter));
  }
  function openAll() {
    const { count, avg, dist } = DATA;
    $("[data-rv-all-title]").innerHTML = `${Number(avg).toFixed(1)} ${stars(avg, "lg")}<small>${count} review${count > 1 ? "s" : ""}</small>`;
    const max = Math.max(1, ...Object.values(dist || {}).map(Number));
    $("[data-rv-dist]").innerHTML = [5, 4, 3, 2, 1].map((s) => {
      const n = +(dist?.[s] || 0);
      return `<button type="button" class="rv-bar" data-rv-f="${s}" ${n ? "" : "disabled"}><span>${s} ★</span><i style="--w:${(100 * n) / max}%"></i><span>${n}</span></button>`;
    }).join("");
    const withPics = DATA.reviews.filter((r) => r.photos.length).length;
    $("[data-rv-chips]").innerHTML = `<button type="button" class="rv-chip" data-rv-f="all">All</button>` +
      (withPics ? `<button type="button" class="rv-chip" data-rv-f="photos">With photos · ${withPics}</button>` : "");
    filter = "all"; page = 0; renderAll();
    open(allDlg);
    $(".order-form", allDlg).scrollTop = 0;
    track("reviews_all_opened", {});
  }
  $("[data-rv-all-open]").addEventListener("click", openAll);
  $("[data-rv-all-close]").addEventListener("click", () => shut(allDlg));
  allDlg.addEventListener("click", (e) => {
    if (e.target === allDlg) return shut(allDlg);
    const f = e.target.closest("[data-rv-f]");
    if (f) { filter = filter === f.dataset.rvF && f.dataset.rvF !== "all" ? "all" : f.dataset.rvF; page = 0; renderAll(); }
  });
  $("[data-rv-more]").addEventListener("click", () => { page++; renderAll(); });

  /* ---------- write a review ---------- */
  const dlg = $("[data-rv-dlg]"), form = $("[data-rv-form]"), done = $("[data-rv-done]");
  const msg = $("[data-rv-msg]"), submit = $("[data-rv-submit]"), up = $("[data-rv-up]"), addTile = $("[data-rv-add]");
  let rating = 0, shots = [];    // shots: [{id, full: Blob, thumb: Blob, url}]
  phoneInput(form.elements.phone);

  const setRating = (v) => {
    rating = v;
    $$("[data-rv-rate] button").forEach((b) => { b.setAttribute("aria-checked", +b.dataset.v === v); b.classList.toggle("on", +b.dataset.v <= v); });
    $("[data-rv-rate-field]").classList.remove("bad");
  };
  $("[data-rv-rate]").addEventListener("click", (e) => { const b = e.target.closest("button"); if (b) setRating(+b.dataset.v); });
  $("[data-rv-rate]").addEventListener("keydown", (e) => {
    const d = { ArrowRight: 1, ArrowUp: 1, ArrowLeft: -1, ArrowDown: -1 }[e.key];
    if (!d) return;
    e.preventDefault(); setRating(Math.min(5, Math.max(1, (rating || 0) + d)));
    $(`[data-rv-rate] [data-v="${rating}"]`).focus();
  });

  // Shrink on the phone before uploading: ≤1600 px photo + ≤480 px thumbnail, JPEG. Redrawing drops EXIF (GPS).
  async function decode(file) {
    try { return await createImageBitmap(file, { imageOrientation: "from-image" }); } catch {}
    const url = URL.createObjectURL(file);
    try { const img = new Image(); img.src = url; await img.decode(); return img; } finally { setTimeout(() => URL.revokeObjectURL(url), 1000); }
  }
  function toJpeg(src, max, q) {
    const w = src.width, h = src.height, s = Math.min(1, max / Math.max(w, h));
    const c = document.createElement("canvas");
    c.width = Math.round(w * s); c.height = Math.round(h * s);
    const g = c.getContext("2d"); g.fillStyle = "#fff"; g.fillRect(0, 0, c.width, c.height); g.drawImage(src, 0, 0, c.width, c.height);
    return new Promise((res, rej) => c.toBlob((b) => (b ? res(b) : rej(new Error("encode"))), "image/jpeg", q));
  }
  const uuid = () => (crypto.randomUUID ? crypto.randomUUID()
    : "10000000-1000-4000-8000-100000000000".replace(/[018]/g, (c) => (c ^ (crypto.getRandomValues(new Uint8Array(1))[0] & (15 >> (c / 4)))).toString(16)));

  function drawShots() {
    $$(".rv-shot", up).forEach((el) => el.remove());
    shots.forEach((s, i) => addTile.insertAdjacentHTML("beforebegin",
      `<div class="rv-shot${s.busy ? " busy" : ""}"><img src="${s.url || ""}" alt="">${s.busy ? "" : `<button type="button" aria-label="Remove photo" data-rv-rm="${i}">×</button>`}</div>`));
    addTile.hidden = shots.length >= MAX_PHOTOS;
  }
  $("[data-rv-file]").addEventListener("change", async (e) => {
    const files = [...e.target.files].filter((f) => f.type.startsWith("image/") || /\.(heic|heif|jpe?g|png|webp)$/i.test(f.name))
      .slice(0, MAX_PHOTOS - shots.length);
    e.target.value = "";
    msg.hidden = true;
    for (const f of files) {
      const s = { id: uuid(), busy: true }; shots.push(s); drawShots();
      try {
        const bmp = await decode(f);
        [s.full, s.thumb] = await Promise.all([toJpeg(bmp, 1600, 0.82), toJpeg(bmp, 480, 0.78)]);
        bmp.close?.();
        s.url = URL.createObjectURL(s.thumb); s.busy = false;
      } catch {
        shots = shots.filter((x) => x !== s);
        msg.textContent = "That photo couldn’t be read. Try another one."; msg.hidden = false;
      }
      drawShots();
    }
  });
  up.addEventListener("click", (e) => {
    const rm = e.target.closest("[data-rv-rm]");
    if (!rm) return;
    const [s] = shots.splice(+rm.dataset.rvRm, 1);
    if (s?.url) URL.revokeObjectURL(s.url);
    drawShots();
  });

  const rules = {
    body: (v) => v.trim().length >= 10,
    name: (v) => v.trim().length >= 2,
    phone: validPhone,
  };
  const check = (n) => { const el = form.elements[n], ok = rules[n](el.value); el.closest(".field").classList.toggle("bad", !ok); return ok; };
  Object.keys(rules).forEach((n) => form.elements[n].addEventListener("blur", () => { if (form.elements[n].value) check(n); }));

  async function upload(path, blob) {
    const res = await fetch(`${CFG.supabaseUrl}/storage/v1/object/reviews/${path}`, {
      method: "POST", headers: { apikey: CFG.supabaseKey, "Content-Type": "image/jpeg", "x-upsert": "false" }, body: blob });
    if (!res.ok) throw new Error("upload " + res.status);
  }

  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    msg.hidden = true;
    const bad = Object.keys(rules).filter((n) => !check(n));
    $("[data-rv-rate-field]").classList.toggle("bad", !rating);
    if (!rating) { $("[data-rv-rate] button").focus(); return; }
    if (bad.length) { form.elements[bad[0]].focus(); return; }
    if (shots.some((s) => s.busy)) { msg.textContent = "One moment, the photos are still loading."; msg.hidden = false; return; }
    submit.disabled = true;
    const label = submit.firstChild;
    try {
      for (let i = 0; i < shots.length; i++) {
        label.textContent = shots.length > 1 ? `Uploading photo ${i + 1} of ${shots.length}… ` : "Uploading photo… ";
        if (!shots[i].sent) { await upload(`r/${shots[i].id}.jpg`, shots[i].full); await upload(`r/${shots[i].id}-t.jpg`, shots[i].thumb); shots[i].sent = true; }
      }
      label.textContent = "Posting… ";
      const f = form.elements;
      const out = await rpc("submit_review", { p: {
        rating, body: f.body.value, name: f.name.value, phone: f.phone.value.replace(/\D/g, ""), website: f.website.value,
        photos: shots.map((s) => s.id), session_id: window.glimp?.session()?.session_id || null } });
      if (!out.ok) {
        if (rules[out.error]) { check(out.error); form.elements[out.error].focus(); return; }
        msg.textContent = out.error === "limit" ? "That’s a lot of reviews from one number today. Try tomorrow."
          : out.error === "photo" ? "A photo didn’t upload. Remove it and try again." : "Something went wrong. Try again.";
        msg.hidden = false; return;
      }
      track("review_submitted", { rating, photos: shots.length });
      $("[data-rv-done-title]").textContent = `Thanks, ${f.name.value.trim().split(/\s+/)[0].replace(/^./, (c) => c.toUpperCase())}.`;
      form.hidden = true; done.hidden = false;
      $("button", done).focus();
    } catch {
      msg.textContent = "That didn’t go through. Check your internet and try again."; msg.hidden = false;
    } finally {
      submit.disabled = false; label.textContent = "Post review ";
    }
  });

  function openForm() {
    if (!form.hidden && dlg.open) return;
    form.hidden = false; done.hidden = true; msg.hidden = true;   // a half-written review stays if they close and come back
    open(dlg);
    track("review_form_opened", {});
  }
  function closeForm() {
    shut(dlg);
    if (!done.hidden) {     // posted: start fresh next time
      form.reset(); setRating(0); shots.forEach((s) => s.url && URL.revokeObjectURL(s.url)); shots = []; drawShots();
      $$(".field", form).forEach((f) => f.classList.remove("bad"));
    }
    if (location.hash === "#review") history.replaceState(null, "", location.pathname + location.search);
  }
  $("[data-rv-write]").addEventListener("click", openForm);
  $$("[data-rv-close]", dlg).forEach((b) => b.addEventListener("click", closeForm));
  dlg.addEventListener("click", (e) => { if (e.target === dlg) closeForm(); });
  dlg.addEventListener("cancel", (e) => { e.preventDefault(); closeForm(); });
  // glimp.in/#review opens the form (for WhatsApp/email asks and the footer link)
  window.addEventListener("hashchange", () => { if (location.hash === "#review") openForm(); });

  load();
})();
