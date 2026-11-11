/**
 * Glimp pre-orders → Google Sheet.
 * Paste this whole file into the Sheet's Apps Script editor (Extensions → Apps Script) and deploy it
 * as a Web app. Steps: website/ORDERS-SETUP.md
 *
 * Every order becomes one row on the "Orders" tab with an order number (GLP-0001, GLP-0002 …),
 * and you get an email for each one.
 */

const PRICE = 1490;
const COLOURS = ["Black", "White", "Red", "Yellow", "Blue", "Lime", "Teal", "Grey"];
const HEADERS = ["Order", "Placed at", "Name", "Phone", "Address", "City", "State", "Pincode",
                 "Colour", "Qty", "Total (₹)", "Note", "Status", "Called?"];

function doPost(e) {
  const p = (e && e.parameter) || {};
  try {
    if (p.website) return json({ ok: true, order: "GLP-0000" });          // honeypot filled → bot, pretend success

    const o = {
      name: clean(p.name, 80), phone: String(p.phone || "").replace(/\D/g, "").slice(-10),
      address: clean(p.address, 300), city: clean(p.city, 60), state: clean(p.state, 60),
      pincode: String(p.pincode || "").replace(/\D/g, ""), colour: clean(p.colour, 20),
      qty: Math.max(1, Math.min(5, parseInt(p.qty, 10) || 1)), note: clean(p.note, 300),
    };
    if (o.name.length < 2) return json({ ok: false, error: "name" });
    if (!/^[6-9]\d{9}$/.test(o.phone)) return json({ ok: false, error: "phone" });
    if (o.address.length < 8) return json({ ok: false, error: "address" });
    if (!/^[1-9]\d{5}$/.test(o.pincode)) return json({ ok: false, error: "pincode" });
    if (COLOURS.indexOf(o.colour) < 0) return json({ ok: false, error: "colour" });

    const lock = LockService.getScriptLock();
    lock.waitLock(20000);
    let id;
    try {
      const sheet = ordersSheet();
      id = "GLP-" + String(sheet.getLastRow()).padStart(4, "0");          // row 1 is the header
      sheet.appendRow([id, new Date(), o.name, "'" + o.phone, o.address, o.city, o.state, "'" + o.pincode,
                       o.colour, o.qty, o.qty * PRICE, o.note, "New", ""]);
    } finally {
      lock.releaseLock();
    }

    try {
      MailApp.sendEmail(Session.getEffectiveUser().getEmail(),
        `New Glimp order ${id}: ${o.qty} × ${o.colour}`,
        `${o.name}  ·  +91 ${o.phone}\n${o.address}\n${o.city}, ${o.state} ${o.pincode}\n\n` +
        `${o.qty} × Glimp ${o.colour}  =  ₹${(o.qty * PRICE).toLocaleString("en-IN")} (COD)\n` +
        (o.note ? `Note: ${o.note}\n` : "") + `\nCall them to confirm.`);
    } catch (mailErr) { /* the order is saved even if the email fails */ }

    return json({ ok: true, order: id });
  } catch (err) {
    return json({ ok: false, error: "server" });
  }
}

function doGet() { return json({ ok: true, service: "glimp-orders" }); }

function ordersSheet() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sh = ss.getSheetByName("Orders");
  if (!sh) {
    sh = ss.insertSheet("Orders");
    sh.appendRow(HEADERS);
    sh.setFrozenRows(1);
    sh.getRange(1, 1, 1, HEADERS.length).setFontWeight("bold");
  }
  return sh;
}

function clean(v, max) { return String(v || "").replace(/[\r\n\t]+/g, " ").replace(/^[=+\-@]+/, "").trim().slice(0, max); }
function json(o) { return ContentService.createTextOutput(JSON.stringify(o)).setMimeType(ContentService.MimeType.JSON); }

/** Run this once from the editor (select "setup" → Run) to create the Orders tab and grant permissions. */
function setup() { ordersSheet(); MailApp.getRemainingDailyQuota(); }
