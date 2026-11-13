# Glimp website

glimp.in: a static site on GitHub Pages, with orders, stock and analytics in Supabase. There's no build step.

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
It's live about a minute later. `CNAME` holds the domain, so don't delete it. DNS is at GoDaddy: 4 A records point to GitHub, and the `www` CNAME points to yash1463.github.io.

## Still to fill in
- Real stock numbers on /admin → Stock (each colour starts at a placeholder 10)
- The three generated images (`IMAGES.md`)

## Rebuilding images
`python website/tools/build_assets.py` regenerates everything in `assets/`: X1 angles per colour, sample photos, looks rendered by `lab/retro.py`, app pages and the brand kit.
