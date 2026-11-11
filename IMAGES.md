# Images to generate for the Glimp site

Three lifestyle shots that need generating. Everything else on the site already uses the real camera renders and the sample photos.
For each one, attach the listed reference photos so the generator keeps the camera's real shape (the button layout, the screen, the loop for the strap).

General rules for all three:
- Show the **back** of the camera (screen + 3 buttons). The front carries the supplier's "THUMB CAMERA / 1984" print, so keep it out of frame.
- Don't add any text, logos or watermarks.
- Natural light, a slight film look, real skin and a real Indian setting. It should look like a photo, not a glossy 3D render.
- Export at the size listed, as JPG or PNG. Send them to me and I'll drop them in.

---

## 1. Hero: camera on keys, in a hand (most important)

**Where it goes:** the big photo at the top of the page (replaces the beach-shack sample photo). The headline sits over the **bottom-left**, so keep that area calm and darker.
**Size:** 2400 × 1500 px (landscape, 16:10). Also make a 1200 × 1600 crop (portrait) for phones if the tool allows.
**Reference photos to attach:**
- `XM17/white camera-4.jpg` (or `white camera-3.jpg`)
- `XM17/yellow camera-4.jpg` (if you want a second colour on the ring)
- `shopify-images/00-hero.jpg` (shows the screen with a photo on it)

**Prompt:**
> A candid lifestyle photo of a young Indian woman's hand holding a bunch of house keys on a metal key ring. Hanging from the ring next to the keys is a tiny white rectangular keychain digital camera, about the size of a thumb, exactly matching the reference images: a white rounded-rectangle body with a small square viewfinder on the left, a dark rectangular screen in the middle and three round black buttons stacked on the right, a small loop on the left side for the strap. The camera's back faces the viewer and its screen shows a tiny warm photo. Background: a softly blurred Mumbai street at golden hour, a chai stall and an auto rickshaw out of focus. Shot on 35 mm film, natural warm evening light, shallow depth of field, gentle grain, true-to-life colours. The hand and keys are in the upper-right two-thirds of the frame; the lower-left third is darker, out-of-focus background with no objects. No text, no logos.

---

## 2. Scale: "Goes where your keys go."

**Where it goes:** the black band under "Why Glimp" (left image). It sits on a black page, so a darker, moody image works best.
**Size:** 1600 × 1360 px (about 4:3.4).
**Reference photos to attach:** `XM17/black camera-4.jpg`, `XM17/red video camera-4.jpg`

**Prompt:**
> A close-up photo of a tiny red keychain digital camera clipped onto a key ring with two brass house keys and a small plastic tag, lying on a dark wooden table. The camera matches the reference images exactly: rounded rectangular body, small square viewfinder on the left, dark rectangular screen, three round black buttons on the right, a loop on the left side for the ring. Show the back of the camera. The camera is about as long as one of the keys, so the scale is obvious. Low, warm side light from a window, deep shadows, dark background, 35 mm film look, fine grain, true-to-life colours. No text, no logos.

---

## 3. In the box: flat lay

**Where it goes:** "Everything. Even the bit everyone forgets." (left image, square).
**Size:** 1600 × 1600 px (square).
**Reference photos to attach:** `XM17/white camera-3.jpg`, `shopify-images/09-ports.jpg`, plus a phone photo of the real cable, converter, strap and SD card if you have them (this makes it much more accurate).

**Prompt:**
> A tidy top-down flat lay on a plain warm off-white paper background (#F4F3EF). Laid out in a neat grid with even spacing: a tiny white rectangular keychain digital camera matching the reference images (back view, screen and three round buttons visible); a microSD card; a short black lanyard-style keychain strap; a short white USB-A to USB-C cable, loosely coiled; and a small white USB-A (female) to USB-C (male) adapter. Soft, even daylight from the top left, very soft shadows, realistic product photography, no reflections. Leave some empty space around each item. No text, no logos, no packaging.

---

## After you send them

I'll export them as WebP, put them in `assets/photos/`, and swap the three slots (they're marked `IMAGE SLOT` in `index.html`). The beach-shack sample photo then moves down into the photo wall.

## Later: real photos from the camera

The photo wall and the "looks" row use stock photos run through the app's look. They're labelled "Sample photos, illustrative" on the page, because they weren't taken on Glimp (ASCI rules). Once you have real shots from the camera, put them in `assets/photos/` and edit the `PHOTOS` list at the top of `main.js`. Then change the label under the wall to "Shot on Glimp".
