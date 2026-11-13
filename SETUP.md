# Turn on orders, stock and analytics (about 15 minutes)

Everything lives in the Supabase project the app already uses (`vuiqgyllynhgekmcaqij`). Nothing here touches the app's own tables.

## 1. Create the tables (once)
1. Go to **supabase.com** → sign in → open the project.
2. In the left bar, click **SQL Editor** → **+ New query**.
3. Open `website/backend/supabase.sql` in VS Code, select all, copy, paste it into the editor.
4. Click **Run** (bottom right). It should say *Success. No rows returned*.
   It's safe to run again later; it never deletes data.

## 2. Make your admin login
1. Left bar → **Authentication** → **Users** → **Add user** → **Create new user**.
2. Enter your email and a strong password. Tick **Auto Confirm User**. Click **Create user**.
3. Back in **SQL Editor** → **+ New query**, paste this with your email, then **Run**:
   ```sql
   insert into site_admins (email) values ('your@email.com') on conflict do nothing;
   ```
4. Open **glimp.in/admin** and sign in. Signing in also marks that device as yours, so your own visits stop counting.

## 3. Set your real stock
**glimp.in/admin → Stock.** Every colour starts at **10** as a placeholder. Type the real number and press **Set to**.
When a new batch arrives, type how many came and press **Add**.
Orders take stock out automatically. Cancelled and RTO orders put it back. When a colour hits 0, the site shows it as sold out and offers "Notify me".

## 4. Microsoft Clarity: heatmaps and recordings (free)
1. Go to **clarity.microsoft.com** → sign in → **+ New project** → Name `Glimp`, URL `https://glimp.in` → **Add new project**.
2. Skip the install screen ("Install manually" → just close it).
3. **Settings** → **Masking** → choose **Strict** (hides all text people type).
4. **Settings** → **Overview** → copy the **Project ID** (about 10 letters).
5. Paste it into `website/config.js`: `clarityId: "abcd123xyz",` then push.
Clarity only loads for visitors who accept analytics cookies.

## 5. Meta Pixel (when you're ready)
1. **business.facebook.com** → **Events Manager** → **Connect data sources** → **Web** → name it `Glimp` → **Create**.
2. Copy the **Pixel ID** (a long number) into `website/config.js`: `metaPixelId: "1234567890",` then push.
It only loads for visitors who accept marketing cookies, and sends PageView, ViewContent, InitiateCheckout and Purchase.

## 6. Tag your ad links
Use this as the ad's **Website URL** in Meta Ads Manager (Ad level → Destination):
```
https://glimp.in/?utm_source=facebook&utm_medium=paid_social&utm_campaign={{campaign.name}}&utm_content={{ad.name}}
```
Meta fills in the names. The admin **Ads** table then shows sessions, bounces and orders per ad.
For the Instagram bio use `https://glimp.in/#order?utm_source=instagram&utm_medium=bio`, and for WhatsApp shares `…?utm_source=whatsapp`.

## 7. Daily routine
- **Orders tab → To call**: call each buyer, then press **Confirmed**, **No answer**, **Call later** or **Cancel** (with a reason).
- When you ship: pick the courier, type the tracking number, press **Shipped**. Later press **Delivered** or **RTO**.
- **Stock tab → Meta ad spend**: type yesterday's spend from Ads Manager. That gives you CAC and ROAS on *delivered* orders.

## Test without messing up the numbers
Open **glimp.in/?glimp_internal=1** once on each phone or laptop you use. That device's visits are then left out, and its orders are marked **test**. (`?glimp_internal=0` undoes it.) You can also mark any order as test on the Orders tab.

## Good to know
- The Supabase free plan pauses a project after 7 days with no traffic at all. Normal site visits keep it awake.
- The publishable key in `config.js` is meant to be public. Visitors can only call four functions: send events, place an order, read stock, and ask for a restock alert. All the data is readable only by emails in `site_admins`.
