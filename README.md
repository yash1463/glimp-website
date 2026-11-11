# Glimp website

A static site with no build step: `index.html`, `styles.css`, `main.js` and `assets/`. Built from `Glimp_Website_Reference/README.md`.

## Preview locally

```
cd website
python -m http.server 8765
```
Then open http://localhost:8765. For the phone layout, open http://localhost:8765/tools/mobile-check.html, or use Chrome DevTools at 390 px.

## Before going live: things to fill in

1. **Store links**: the top of `main.js` (`STORE`). Set `base` to your Shopify domain and the product handle for each of the 8 colours. Until `base` is set, every "Pre-order" button scrolls to the colour picker instead of going to Shopify.
2. **Instagram, WhatsApp and email**: same block in `main.js`.
3. **Policies**: footer links point to Shopify's standard `/policies/shipping-policy`, `refund-policy` and `privacy-policy` pages. Create those in Shopify (Settings → Policies).
4. **Generated images**: see `IMAGES.md` (hero, scale shot, in-the-box flat lay).
5. **Social share image**: `assets/og-image.jpg`. Once the domain exists, change the `og:image` URL in `index.html` to the full address (`https://yourdomain/assets/og-image.jpg`).

## Hosting

Live at https://glimp.in via GitHub Pages (repo `yash1463/glimp-website`, branch `main`, root folder).
To update the site: edit, then `git add -A && git commit -m "..." && git push`. It's live in about a minute.
`CNAME` holds the domain, so don't delete it. DNS is at GoDaddy (4 A records to GitHub, `www` CNAME to yash1463.github.io).
If Shopify gets its own subdomain later, use `shop.glimp.in` so this site keeps `glimp.in`.

## Rebuilding images

`python website/tools/build_assets.py` regenerates everything in `assets/` from the source folders (camera cut-outs, samples, app pages, brand kit).
