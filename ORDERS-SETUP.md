# Set up pre-orders (Google Sheet): about 5 minutes

The site's pre-order form sends each order to a Google Sheet you own. Each order gets its own row and an order number (GLP-0001 …), and Google emails you for every one.

## 1. Make the Sheet
1. Go to **sheets.google.com** and sign in with the Google account that should receive the order emails.
2. Click **Blank spreadsheet**. Name it **Glimp orders** (click "Untitled spreadsheet" at the top left).

## 2. Paste the script
1. In the Sheet's menu, click **Extensions → Apps Script**. A new tab opens with a file called `Code.gs`.
2. Select everything in that file and delete it.
3. Open `website/tools/order-sheet.gs` on your laptop (in VS Code), copy all of it and paste it in.
4. Click the **💾 Save** icon.

## 3. Allow it once
1. In the dropdown next to **▷ Run** (top bar), choose **setup**, then click **▷ Run**.
2. A box says "Authorization required". Click **Review permissions** and pick your account.
3. Google shows "Google hasn't verified this app". That's expected, because it's your own script. Click **Advanced → Go to Untitled project (unsafe) → Allow**.
4. Go back to the Sheet tab. A tab called **Orders** with column headings now exists.

## 4. Publish it as a web app
1. In Apps Script, click the blue **Deploy → New deployment**.
2. Click the ⚙️ next to "Select type" and choose **Web app**.
3. Set these:
   - Description: `Glimp orders`
   - Execute as: **Me**
   - Who has access: **Anyone**. This only lets the website send orders in. Nobody can read your Sheet.
4. Click **Deploy**, then copy the **Web app URL** (it ends in `/exec`).
5. Send me that URL, or paste it into `website/main.js` yourself:
   `const ORDER_ENDPOINT = "https://script.google.com/macros/s/…/exec";`
   Then push.

## Using it
- New orders show up at the bottom of the **Orders** tab with status **New**. Call the buyer, then change Status (for example to Confirmed, Shipped, Delivered or Cancelled) and tick **Called?**
- Share the Sheet with a teammate the normal way (Share button). They don't need anything else.
- **glimp.in/#order** opens the form directly, and **glimp.in/#order-teal** opens it with a colour already picked. Use these in your Instagram bio and ads.

## If you change the script later
Use **Deploy → Manage deployments → ✏️ Edit → Version: New version → Deploy**. That keeps the same URL, so the website doesn't need changing.
