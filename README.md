# Glimp website

glimp.in: a static site on Cloudflare Pages, with orders, stock and analytics in Supabase. There's no build step.

| File | What it is |
|---|---|
| `index.html`, `styles.css`, `main.js` | The page: colour gallery, order form, stock-aware buttons |
| `config.js` | **Settings**: Supabase URL and key, Clarity ID, Meta Pixel ID, WhatsApp, Instagram, email |
| `analytics.js` | Cookie banner + event tracking (contract: `../glimp-analytics-spec/03-event-taxonomy.md`) |
| `admin/` | glimp.in/admin: overview, orders, stock and behaviour (admins only) |
| `backend/supabase.sql` | All tables and functions. Paste into Supabase once (see `SETUP.md`) |
| `privacy.html` | Privacy notice linked from the cookie banner |
| `SETUP.md` | Step-by-step: database, admin login, stock, Clarity, Pixel, ad links |
| `IMAGES.md` | The three lifestyle renders still to make |
| `tools/` | `build_assets.py` (all images), `serve.py` (local preview), `mobile-check.html` |

## Preview locally
```
python website/tools/serve.py
```
Then open http://localhost:8765 (phone layout: http://localhost:8765/tools/mobile-check.html).

## Update the live site
```
cd website
git add -A && git commit -m "what changed" && git push
```
It's live about a minute later. Cloudflare Pages watches the `main` branch of yash1463/glimp-website and publishes the repo folder as-is, with no build command. Each deploy is listed under Workers & Pages → glimp-website → Deployments, and any earlier one can be rolled back from there.

**Hosting:** the domain is registered at GoDaddy, but its DNS lives in Cloudflare (nameservers changed at GoDaddy). Email for yash@glimp.in is still GoDaddy's, so the MX, SPF, DMARC and `email` records in Cloudflare DNS must stay grey-cloud (DNS only). `www` redirects to glimp.in with a Cloudflare Redirect Rule. `_headers` sets the security and image-cache headers.

## Still to fill in
- Real stock numbers on /admin → Stock (each colour starts at a placeholder 10)
- The three generated images (`IMAGES.md`)

## Rebuilding images
`python website/tools/build_assets.py` regenerates everything in `assets/`: X1 angles per colour, sample photos, looks rendered by `lab/retro.py`, app pages and the brand kit.
