/* glimp.in settings. Everything here is public by design (the Supabase key is the publishable one). */
window.GLIMP_CONFIG = {
  supabaseUrl: "https://vuiqgyllynhgekmcaqij.supabase.co",
  supabaseKey: "sb_publishable_7OCmOLV6JWpj277awj1XbQ_Z9jeCkc8",
  clarityId: "",        // Microsoft Clarity project ID (clarity.microsoft.com → Settings → Overview)
  metaPixelId: "",      // Meta Pixel ID (Events Manager → Data sources), leave empty until you have one
  version: "2026-11-13",
  debug: /[?&]debug=1/.test(location.search),
  contact: {
    whatsapp: "https://wa.me/91XXXXXXXXXX",   // TODO: your number
    instagram: "https://instagram.com/",      // TODO: your handle
    email: "mailto:hello@glimp.in",           // TODO: your address
  },
};
