# Glimp website

A static site with no build step: `index.html`, `styles.css`, `main.js` and `assets/`. Built from `Glimp_Website_Reference/README.md`.

## Preview locally

```
cd website
python -m http.server 8765
```
Then open http://localhost:8765. For the phone layout, open http://localhost:8765/tools/mobile-check.html, or use Chrome DevTools at 390 px.

## Before going live: things to fill in

1. **Instagram, WhatsApp and email**: the `CONTACT` block at the top of `main.js`.
2. **Orders**: no Shopify. The site takes orders itself.
3. **Generated images**: see `IMAGES.md` (hero, scale shot, in-the-box flat lay).

## Hosting

Live at https://glimp.in via GitHub Pages (repo `yash1463/glimp-website`, branch `main`, root folder).
To update the site: edit, then `git add -A && git commit -m "..." && git push`. It's live in about a minute.
`CNAME` holds the domain, so don't delete it. DNS is at GoDaddy (4 A records to GitHub, `www` CNAME to yash1463.github.io).

## Rebuilding images

`python website/tools/build_assets.py` regenerates everything in `assets/` from the source folders (camera cut-outs, samples, app pages, brand kit).
