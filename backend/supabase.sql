-- ════════════════════════════════════════════════════════════════════════════
-- glimp.in — orders, stock and analytics on Supabase
-- Right-sized from glimp-analytics-spec (Phase 0 + 1, light Phase 3).
-- Paste this whole file into Supabase → SQL Editor → Run. Safe to run again.
--
-- Security model
--   • Visitors (anon key) can only call 4 functions: ingest, place_order, get_stock, notify_restock.
--   • Every table has RLS on with no public policies, so nobody can read rows with the anon key.
--   • /admin signs in with Supabase Auth; only emails in site_admins pass is_site_admin().
--     (The app's anonymous sign-ins are "authenticated" too, which is why we check the email list,
--      never the role.)
--   • Personal data (name, phone, address) lives only in orders / restock_requests.
--     Analytics events never hold it: ingest() rejects props that look like a phone or email.
-- ════════════════════════════════════════════════════════════════════════════

-- gen_random_uuid() is built into Postgres 13+, no extension needed.

-- ───────────────────────── Admins ─────────────────────────
create table if not exists site_admins (email text primary key);
alter table site_admins enable row level security;

create or replace function is_site_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from site_admins
                 where lower(email) = lower(coalesce(auth.jwt() ->> 'email', '')));
$$;

-- ───────────────────────── Stock ─────────────────────────
create table if not exists inventory (
  colour     text primary key,
  on_hand    int  not null default 0 check (on_hand >= 0),
  low_at     int  not null default 5,
  sort       int  not null default 0,
  updated_at timestamptz not null default now()
);
-- Starting numbers are placeholders: set the real ones on /admin → Stock.
insert into inventory (colour, on_hand, sort) values
  ('white', 10, 2), ('red', 10, 3), ('yellow', 10, 4), ('teal', 10, 7), ('grey', 10, 8)
on conflict (colour) do nothing;

create table if not exists inventory_moves (
  id         bigserial primary key,
  colour     text not null references inventory(colour),
  delta      int  not null,
  reason     text not null check (reason in ('order','cancel','rto','restock','adjust','return')),
  order_no   text,
  note       text,
  created_at timestamptz not null default now(),
  created_by text
);
alter table inventory       enable row level security;
alter table inventory_moves enable row level security;

create table if not exists restock_requests (
  id         bigserial primary key,
  colour     text not null references inventory(colour),
  phone      text not null,
  session_id text,
  created_at timestamptz not null default now(),
  notified   boolean not null default false
);
alter table restock_requests enable row level security;

-- ───────────────────────── Orders ─────────────────────────
create sequence if not exists order_no_seq;

create table if not exists orders (
  order_id          uuid primary key default gen_random_uuid(),
  order_no          text unique not null,
  created_at        timestamptz not null default now(),
  -- customer (personal data: admin only)
  name              text not null,
  phone             text not null,
  address           text not null,
  city              text not null,
  state             text not null,
  pincode           text not null,
  note              text,
  -- what
  colour            text not null references inventory(colour),
  qty               int  not null check (qty between 1 and 5),
  value_paise       int  not null,
  payment_method    text not null default 'cod',
  -- COD lifecycle
  status            text not null default 'created'
                    check (status in ('created','confirmed','cancelled','shipped','delivered','rto','returned')),
  status_updated_at timestamptz,
  call_attempts     int  not null default 0,
  last_call_outcome text,
  courier           text,
  awb               text,
  -- analytics link (no personal data)
  session_id        text,
  anonymous_id      uuid,
  attr              jsonb,
  channel           text,
  device_type       text,
  is_test           boolean not null default false,
  source            text not null default 'web'
);
create index if not exists orders_created_idx on orders (created_at);
create index if not exists orders_session_idx on orders (session_id);
alter table orders enable row level security;
alter table orders add column if not exists email text;   -- asked on the order form (2026-11-21)

create table if not exists order_status_events (
  id         bigserial primary key,
  order_id   uuid not null references orders(order_id),
  status     text not null,     -- created|call_attempted|confirmed|cancelled|shipped|delivered|rto|returned
  reason     text,
  attempt_no int,
  meta       jsonb,
  created_at timestamptz not null default now(),
  created_by text
);
alter table order_status_events enable row level security;

-- Black, blue and lime are no longer sold (2026-11-21). Remove them; if something
-- already points at a row (an order, a stock move, a notify-me), keep it at 0 so it can't be ordered.
delete from inventory i where i.colour in ('black', 'blue', 'lime')
  and not exists (select 1 from inventory_moves m where m.colour = i.colour)
  and not exists (select 1 from orders o where o.colour = i.colour)
  and not exists (select 1 from restock_requests r where r.colour = i.colour);
update inventory set on_hand = 0 where colour in ('black', 'blue', 'lime');

-- ───────────────────────── Ad spend (typed in on /admin) ─────────────────────────
create table if not exists ad_spend_daily (
  date        date primary key,
  spend_paise int  not null check (spend_paise >= 0),
  updated_at  timestamptz not null default now()
);
alter table ad_spend_daily enable row level security;

-- ───────────────────────── Events ─────────────────────────
create table if not exists events (
  event_id        uuid        primary key,
  event_name      text        not null,
  source          text        not null default 'browser',
  client_ts       timestamptz,
  received_at     timestamptz not null default now(),
  anonymous_id    uuid,
  session_id      text        not null,
  seq             int,
  consent_state   text        not null default 'none',
  page_path       text,
  device_type     text,
  os              text,
  browser         text,
  connection_type text,
  viewport_w      int,
  attr            jsonb,      -- attribution, on the first page_viewed of a session only
  props           jsonb       not null default '{}'::jsonb,
  site_version    text,
  is_bot          boolean     not null default false,
  is_internal     boolean     not null default false
);
create index if not exists events_session_idx   on events (session_id, received_at);
create index if not exists events_name_time_idx on events (event_name, received_at);
create index if not exists events_time_idx      on events (received_at);
alter table events enable row level security;

create table if not exists events_rejected (
  id          bigserial primary key,
  received_at timestamptz not null default now(),
  reason      text not null,
  event_name  text,
  payload     jsonb
);
alter table events_rejected enable row level security;

create table if not exists consent_receipts (
  consent_id     uuid primary key,
  anonymous_id   uuid,
  session_id     text,
  analytics      boolean not null,
  marketing      boolean not null,
  banner_version text not null,
  language       text,
  created_at     timestamptz not null default now()
);
alter table consent_receipts enable row level security;

-- The event contract: glimp-analytics-spec/03-event-taxonomy.md (+ the "glimp.in additions" section).
create or replace function allowed_events() returns text[] language sql immutable as $$
  select array[
    'page_viewed','page_engaged','scroll_depth_reached','section_viewed','page_left','web_vitals_reported',
    'consent_updated','nav_clicked','cta_clicked',
    'product_viewed','colour_swatch_selected','product_image_viewed','comparison_viewed','faq_opened',
    'sample_photo_viewed','notify_me_requested','keycam_app_link_clicked','share_clicked',
    'checkout_started','checkout_field_error','order_placed','form_abandoned',
    'whatsapp_clicked','instagram_clicked','outbound_link_clicked',
    'rage_click','dead_click','js_error','api_error',
    'look_selected','app_usecase_selected'
  ];
$$;

-- Essential events allowed before consent (cookieless, aggregate only). Spec file 02 §3.
create or replace function essential_events() returns text[] language sql immutable as $$
  select array['page_viewed','product_viewed','checkout_started','order_placed','consent_updated'];
$$;

-- ───────────────────────── Collector ─────────────────────────
create or replace function ingest(batch jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  e jsonb; ok int := 0; bad int := 0; ua text := ''; ua_bot boolean;
  why text; props jsonb; attr jsonb; n int;
begin
  if jsonb_typeof(batch) <> 'array' or jsonb_array_length(batch) = 0 or jsonb_array_length(batch) > 50 then
    insert into events_rejected (reason) values ('bad_batch');
    return jsonb_build_object('ok', false, 'error', 'bad_batch');
  end if;
  begin
    ua := coalesce(current_setting('request.headers', true)::jsonb ->> 'user-agent', '');
  exception when others then ua := '';
  end;
  ua_bot := ua ~* '(bot|crawl|spider|slurp|headless|lighthouse|pagespeed|facebookexternalhit|whatsapp/|preview)';

  for e in select value from jsonb_array_elements(batch) loop
    why := null;
    props := coalesce(e -> 'props', '{}'::jsonb);
    attr  := e -> 'attr';
    if not coalesce(e ->> 'event_name' = any (allowed_events()), false) then why := 'unknown_event';
    elsif coalesce(e ->> 'event_id', '') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then why := 'bad_event_id';
    elsif coalesce(length(e ->> 'session_id'), 0) not between 8 and 64 then why := 'bad_session';
    elsif e ? 'anonymous_id' and jsonb_typeof(e -> 'anonymous_id') <> 'null'
          and (e ->> 'anonymous_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then why := 'bad_anonymous_id';
    elsif jsonb_typeof(props) <> 'object' or length(props::text) > 3000 then why := 'bad_props';
    elsif props::text ~ '@|[0-9]{10}' then why := 'pii_guard';
    elsif attr is not null and (jsonb_typeof(attr) <> 'object' or length(attr::text) > 1200) then why := 'bad_attr';
    elsif coalesce(e ->> 'consent_state', 'none') = 'none' and not (e ->> 'event_name' = any (essential_events())) then why := 'no_consent';
    end if;

    if why is not null then
      bad := bad + 1;
      insert into events_rejected (reason, event_name, payload)
      values (why, left(e ->> 'event_name', 60), case when why = 'pii_guard' then null else e end);
      continue;
    end if;

    insert into events (event_id, event_name, client_ts, anonymous_id, session_id, seq, consent_state,
                        page_path, device_type, os, browser, connection_type, viewport_w, attr, props,
                        site_version, is_bot, is_internal)
    values ((e ->> 'event_id')::uuid, e ->> 'event_name',
            case when (e ->> 'client_ts') ~ '^\d{4}-\d\d-\d\dT' then (e ->> 'client_ts')::timestamptz end,
            nullif(e ->> 'anonymous_id', '')::uuid, e ->> 'session_id',
            case when (e ->> 'seq') ~ '^\d{1,6}$' then (e ->> 'seq')::int end,
            left(coalesce(e ->> 'consent_state', 'none'), 24),
            left(e ->> 'page_path', 200), left(e ->> 'device_type', 12), left(e ->> 'os', 20),
            left(e ->> 'browser', 20), left(e ->> 'connection_type', 8),
            case when (e ->> 'viewport_w') ~ '^\d{1,5}$' then (e ->> 'viewport_w')::int end,
            attr, props, left(e ->> 'site_version', 40),
            ua_bot or coalesce((e ->> 'is_bot')::boolean, false),
            coalesce((e ->> 'is_internal')::boolean, false))
    on conflict (event_id) do nothing;
    get diagnostics n = row_count;
    ok := ok + n;

    if e ->> 'event_name' = 'consent_updated' and n = 1 then
      insert into consent_receipts (consent_id, anonymous_id, session_id, analytics, marketing, banner_version, language)
      values ((e ->> 'event_id')::uuid, nullif(e ->> 'anonymous_id', '')::uuid, e ->> 'session_id',
              coalesce((props ->> 'analytics')::boolean, false), coalesce((props ->> 'marketing')::boolean, false),
              coalesce(props ->> 'banner_version', '1'), left(props ->> 'language', 8))
      on conflict do nothing;
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'stored', ok, 'rejected', bad);
end $$;

-- ───────────────────────── Channel grouping (spec file 02 §4) ─────────────────────────
create or replace function channel_of(a jsonb) returns text language sql immutable as $$
  select case
    when a is null then 'direct'
    when coalesce((a ->> 'fbclid')::boolean, false)
      or (lower(a ->> 'utm_medium') in ('cpc','paid','paid_social','ppc')
          and lower(a ->> 'utm_source') in ('facebook','fb','instagram','ig','meta')) then 'paid_social'
    when coalesce((a ->> 'gclid')::boolean, false)
      or (lower(a ->> 'utm_medium') = 'cpc' and lower(a ->> 'utm_source') = 'google') then 'paid_search'
    when lower(a ->> 'utm_source') = 'whatsapp' or a ->> 'referrer_domain' ilike '%whatsapp%' then 'whatsapp'
    when lower(a ->> 'utm_source') = 'qr' then 'offline_qr'
    when lower(a ->> 'utm_medium') = 'email' then 'email'
    when a ->> 'referrer_domain' ~* '(facebook|instagram|t\.co$|twitter|x\.com|linkedin|youtube|reddit)' then 'organic_social'
    when a ->> 'referrer_domain' ~* '(google\.|bing\.|duckduckgo|yahoo\.)' then 'organic_search'
    when coalesce(a ->> 'referrer_domain', '') <> '' or a ? 'ref' or a ? 'utm_source' then 'referral'
    else 'direct'
  end;
$$;

-- ───────────────────────── Sessions (computed live from events) ─────────────────────────
-- At Glimp's volume a view is fast enough. Turn it into a nightly table past ~1M events.
create or replace view sessions_v with (security_invoker = true) as
with s as (
  select session_id,
         min(received_at) as started_at,
         max(received_at) as ended_at,
         (array_agg(anonymous_id) filter (where anonymous_id is not null))[1]           as anonymous_id,
         (array_agg(attr order by received_at) filter (where attr is not null))[1]      as attr,
         (array_agg(device_type order by received_at) filter (where device_type is not null))[1] as device_type,
         (array_agg(page_path order by received_at) filter (where event_name = 'page_viewed'))[1] as landing_path,
         count(*) filter (where event_name = 'page_viewed')                             as pageviews,
         coalesce(sum((props ->> 'engaged_ms')::bigint) filter (where event_name = 'page_left'), 0) as engaged_ms,
         coalesce(max((props ->> 'depth_pct')::int) filter (where event_name = 'scroll_depth_reached'), 0) as max_scroll,
         bool_or(event_name = 'page_engaged')     as engaged_evt,
         bool_or(event_name = 'product_viewed')   as has_product_view,
         bool_or(event_name = 'checkout_started') as has_checkout,
         bool_or(event_name = 'order_placed')     as has_order_browser,
         count(*) filter (where event_name = 'rage_click') as rage_clicks,
         count(*) filter (where event_name = 'js_error')   as js_errors,
         bool_or(is_bot)      as is_bot,
         bool_or(is_internal) as is_internal,
         max(consent_state)   as consent_state
  from events
  group by session_id
)
select s.*,
       (s.started_at at time zone 'Asia/Kolkata')::date as started_date_ist,
       channel_of(s.attr) as channel,
       exists (select 1 from orders o where o.session_id = s.session_id and not o.is_test) as has_order,
       (s.engaged_ms >= 10000 or s.pageviews >= 2 or s.engaged_evt or s.has_checkout) as is_engaged
from s;
revoke all on sessions_v from anon, authenticated;

-- ───────────────────────── Public: stock ─────────────────────────
create or replace function get_stock() returns jsonb
language sql stable security definer set search_path = public as $$
  -- rank 1 = the colour with the most stock (the site opens on it); counts above low_at stay private
  select coalesce(jsonb_object_agg(colour, jsonb_build_object(
           'status', case when on_hand <= 0 then 'out' when on_hand <= low_at then 'low' else 'in' end,
           'left',   case when on_hand between 1 and low_at then on_hand end,
           'rank',   rk)), '{}'::jsonb)
  from (select *, row_number() over (order by on_hand desc, sort) as rk from inventory) i;
$$;

-- ───────────────────────── Order emails + WhatsApp ping ─────────────────────────
-- Sent by Supabase the moment an order is saved (pg_net = async HTTP, it never slows or blocks the order).
--   • Customer: thank-you + order summary from yash@glimp.in (if they gave an email)
--   • Yash: "New order" email to yash@glimp.in, with a one-tap WhatsApp thank-you link
--   • Yash, optional: a short WhatsApp ping through CallMeBot (no name, phone or address in it)
-- Keys live in Supabase Vault, never in this file (SETUP.md → Order emails):
--   select vault.create_secret('re_…', 'resend_api_key');
--   select vault.create_secret('<apikey>', 'callmebot_key');  select vault.create_secret('+91…', 'callmebot_phone');
create extension if not exists pg_net;

create or replace function html_esc(t text) returns text language sql immutable as $$
  select replace(replace(replace(replace(coalesce(t, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;')
$$;

create or replace function url_encode(t text) returns text language sql immutable as $$
  select coalesce(string_agg(case when b between 48 and 57 or b between 65 and 90 or b between 97 and 122 or b in (45, 46, 95, 126)
                                  then chr(b) else '%' || upper(lpad(to_hex(b), 2, '0')) end, '' order by i), '')
  from (select i, get_byte(convert_to(coalesce(t, ''), 'UTF8'), i) as b
        from generate_series(0, length(convert_to(coalesce(t, ''), 'UTF8')) - 1) as i) s
$$;

create or replace function secret(p_name text) returns text
language sql stable security definer set search_path = public as $$
  select decrypted_secret from vault.decrypted_secrets where name = p_name limit 1
$$;
revoke all on function secret(text) from public, anon, authenticated;

create or replace function notify_order(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  o orders%rowtype;
  v_key text := secret('resend_api_key');
  v_cb_key text := secret('callmebot_key');
  v_cb_phone text := secret('callmebot_phone');
  v_colour text; v_first text; v_total text; v_line text; v_tag text;
  p1 text; p2 text; p3 text; p4 text; p5 text; v_wa text; v_ship text; v_html text; v_text text;
begin
  select * into o from orders where order_id = p_id;
  if not found then return; end if;

  v_colour := initcap(o.colour);
  v_first  := initcap(split_part(o.name, ' ', 1));
  v_total  := '₹' || to_char(o.qty * 1690, 'FM999,999');   -- ₹1,690 each, delivery free
  v_line   := format('Glimp · %s × %s', v_colour, o.qty);
  v_tag    := case when o.is_test then '[test] ' else '' end;

  p1 := format('Hi %s 👋', v_first);
  p2 := format('This is Yash, the founder of Glimp. I wanted to personally say thank you. Your order #%s has been received, and you''re one of our early customers. That means a lot to me 🙏', o.order_no);
  p3 := 'I''m packing your Glimp myself and will ship it as soon as possible. I''ll send you the tracking details the moment it''s on its way. It''s Cash on Delivery, so you only pay when it reaches you.';
  p4 := 'If you face any issue at any point, before or after delivery, we''ll give you our utmost support until it''s sorted. Just reply here. You''re talking directly to me.';
  p5 := 'Once it arrives, clip it on, click your first shot, and send it to me. I''ll be waiting to see the first glimpse you catch 📸✨';

  v_ship := format('%s<br>%s<br>%s, %s %s<br>+91 %s', html_esc(o.name), html_esc(o.address), html_esc(o.city), html_esc(o.state), html_esc(o.pincode), html_esc(o.phone));

  if v_key is not null then
    -- 1) the customer
    if o.email is not null then
      v_html := format($h$<div style="background:#f2efe8;padding:24px 12px;font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1c1a17">
<div style="max-width:560px;margin:0 auto;background:#ffffff;border-radius:16px;overflow:hidden">
<img src="https://glimp.in/assets/wa/%s.jpg" width="560" alt="Your Glimp in %s" style="display:block;width:100%%;height:auto;border:0">
<div style="padding:24px 24px 4px;font-size:16px;line-height:1.6">
<p style="margin:0 0 16px">%s</p><p style="margin:0 0 16px">%s</p><p style="margin:0 0 16px">%s</p><p style="margin:0 0 16px">%s</p><p style="margin:0 0 16px">%s</p>
<p style="margin:0 0 20px">Yash<br><span style="color:#6b6760">Founder, Glimp</span></p>
</div>
<div style="margin:0 24px 24px;padding:16px 18px;border:1px solid #e6e2da;border-radius:12px;font-size:14px;line-height:1.6">
<div style="font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12px;letter-spacing:.06em;text-transform:uppercase;color:#6b6760">Order %s</div>
<div style="margin-top:4px"><b>%s</b></div>
<div>Pay on delivery: <b>%s</b> <span style="color:#6b6760">· Free SD card (worth ₹500) · Free delivery</span></div>
<div style="margin-top:12px;color:#6b6760">Ships to</div>
<div>%s</div>
</div>
</div>
<p style="text-align:center;font-size:12px;color:#6b6760;margin:16px 0 0"><a href="https://glimp.in" style="color:#6b6760">glimp.in</a></p>
</div>$h$, o.colour, v_colour, html_esc(p1), html_esc(p2), html_esc(p3), html_esc(p4), html_esc(p5),
        o.order_no, v_line, v_total, v_ship);
      v_text := concat_ws(E'\n\n', p1, p2, p3, p4, p5, E'Yash\nFounder, Glimp',
        format(E'Order %s\n%s\nPay on delivery: %s · Free SD card (worth ₹500) · Free delivery\nShips to: %s, %s, %s, %s %s', o.order_no, v_line, v_total, o.name, o.address, o.city, o.state, o.pincode));
      perform net.http_post(
        url := 'https://api.resend.com/emails',
        headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
        body := jsonb_build_object('from', 'Yash from Glimp <yash@glimp.in>', 'to', jsonb_build_array(o.email),
                                   'reply_to', 'yash@glimp.in', 'subject', v_tag || 'Your Glimp order ' || o.order_no,
                                   'html', v_html, 'text', v_text));
    end if;

    -- 2) Yash
    v_wa := 'https://api.whatsapp.com/send?phone=91' || o.phone || '&text=' ||
            url_encode(concat_ws(E'\n\n', p1, p2, p3, p4, p5, E'Yash\nFounder, Glimp', 'https://glimp.in/c/' || o.colour));
    v_html := format($h$<div style="font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:15px;line-height:1.6;color:#1c1a17">
<p style="margin:0 0 4px;font-size:20px"><b>%s</b> · %s</p>
<p style="margin:0 0 16px;color:#6b6760">%s · %s</p>
<p style="margin:0 0 16px">%s<br>%s</p>
%s
<p style="margin:20px 0">
<a href="%s" style="display:inline-block;padding:10px 18px;border-radius:999px;background:#25d366;color:#ffffff;text-decoration:none;font-weight:600">WhatsApp thank-you</a>
&nbsp; <a href="tel:+91%s" style="display:inline-block;padding:10px 18px;border-radius:999px;border:1px solid #1c1a17;color:#1c1a17;text-decoration:none">Call</a>
&nbsp; <a href="https://glimp.in/admin/" style="color:#1c1a17">Admin</a>
</p>
<p style="margin:0;color:#6b6760;font-size:13px">%s%s</p>
</div>$h$, v_line, v_total, o.order_no, coalesce(o.channel, 'direct'), v_ship,
      case when o.email is not null then html_esc(o.email) else '<span style="color:#6b6760">no email</span>' end,
      case when o.note is not null then '<p style="margin:0 0 16px">Note: ' || html_esc(o.note) || '</p>' else '' end,
      html_esc(v_wa), html_esc(o.phone),
      case when o.is_test then 'Test order. ' else '' end, 'COD · ships in about 20 days');
    perform net.http_post(
      url := 'https://api.resend.com/emails',
      headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
      body := jsonb_build_object('from', 'Glimp orders <yash@glimp.in>', 'to', jsonb_build_array('yash@glimp.in'),
                                 'subject', format('%sNew order %s · %s × %s · %s · %s', v_tag, o.order_no, v_colour, o.qty, v_total, o.city),
                                 'html', v_html));
  end if;

  -- 3) WhatsApp ping to Yash (optional). Third-party service, so no name, phone or address.
  if v_cb_key is not null and v_cb_phone is not null then
    perform net.http_get(
      url := 'https://api.callmebot.com/whatsapp.php',
      params := jsonb_build_object('phone', v_cb_phone, 'apikey', v_cb_key,
                                   'text', format('%s🛒 New order %s · %s × %s · %s · %s', v_tag, o.order_no, v_colour, o.qty, v_total, o.city)));
  end if;
end $$;
revoke all on function notify_order(uuid) from public, anon, authenticated;

-- ───────────────────────── Public: place an order ─────────────────────────
create or replace function place_order(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_name text := left(btrim(regexp_replace(coalesce(p ->> 'name', ''), '\s+', ' ', 'g')), 80);
  v_phone text := right(regexp_replace(coalesce(p ->> 'phone', ''), '\D', '', 'g'), 10);
  v_address text := left(btrim(regexp_replace(coalesce(p ->> 'address', ''), '\s+', ' ', 'g')), 300);
  v_city text := left(btrim(coalesce(p ->> 'city', '')), 60);
  v_state text := left(btrim(coalesce(p ->> 'state', '')), 60);
  v_pin text := regexp_replace(coalesce(p ->> 'pincode', ''), '\D', '', 'g');
  v_colour text := lower(coalesce(p ->> 'colour', ''));
  v_qty int := case when (p ->> 'qty') ~ '^\d{1,2}$' then (p ->> 'qty')::int else 1 end;
  v_note text := nullif(left(btrim(coalesce(p ->> 'note', '')), 300), '');
  v_email text := nullif(lower(btrim(coalesce(p ->> 'email', ''))), '');
  v_session text := left(p ->> 'session_id', 64);
  v_anon uuid := case when (p ->> 'anonymous_id') ~ '^[0-9a-f-]{36}$' then (p ->> 'anonymous_id')::uuid end;
  v_attr jsonb := case when jsonb_typeof(p -> 'attr') = 'object' and length((p -> 'attr')::text) < 1200 then p -> 'attr' end;
  v_test boolean := coalesce((p ->> 'internal')::boolean, false);
  v_stock int; v_no text; v_id uuid; v_recent text;
begin
  if coalesce(p ->> 'website', '') <> '' then                      -- honeypot: a bot filled the hidden field
    return jsonb_build_object('ok', true, 'order', 'GLP-0000');
  end if;
  if length(v_name) < 2 then return jsonb_build_object('ok', false, 'error', 'name'); end if;
  if v_phone !~ '^[6-9][0-9]{9}$' then return jsonb_build_object('ok', false, 'error', 'phone'); end if;
  if length(v_address) < 8 then return jsonb_build_object('ok', false, 'error', 'address'); end if;
  if v_pin !~ '^[1-9][0-9]{5}$' then return jsonb_build_object('ok', false, 'error', 'pincode'); end if;
  if length(v_city) < 2 then return jsonb_build_object('ok', false, 'error', 'city'); end if;
  if v_state = '' then return jsonb_build_object('ok', false, 'error', 'state'); end if;
  if v_email is not null and (length(v_email) > 120 or v_email !~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$') then
    return jsonb_build_object('ok', false, 'error', 'email');
  end if;
  if v_qty not between 1 and 5 then return jsonb_build_object('ok', false, 'error', 'qty'); end if;

  -- double tap on "Place order": hand back the order we just made
  select order_no into v_recent from orders
   where phone = v_phone and colour = v_colour and qty = v_qty and created_at > now() - interval '10 minutes'
   order by created_at desc limit 1;
  if v_recent is not null then return jsonb_build_object('ok', true, 'order', v_recent, 'repeat', true); end if;

  if (select count(*) from orders where phone = v_phone and created_at > now() - interval '24 hours') >= 3 then
    return jsonb_build_object('ok', false, 'error', 'limit');
  end if;

  select on_hand into v_stock from inventory where colour = v_colour for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'colour'); end if;
  if v_stock < v_qty then
    return jsonb_build_object('ok', false, 'error', 'sold_out', 'left', v_stock);
  end if;

  update inventory set on_hand = on_hand - v_qty, updated_at = now() where colour = v_colour;
  v_no := 'GLP-' || lpad(nextval('order_no_seq')::text, 4, '0');

  insert into orders (order_no, name, phone, email, address, city, state, pincode, note, colour, qty, value_paise,
                      session_id, anonymous_id, attr, channel, device_type, is_test)
  values (v_no, v_name, v_phone, v_email, v_address, v_city, v_state, v_pin, v_note, v_colour, v_qty, v_qty * 169000,
          v_session, v_anon, v_attr, channel_of(v_attr), left(p ->> 'device_type', 12), v_test)
  returning order_id into v_id;

  insert into inventory_moves (colour, delta, reason, order_no) values (v_colour, -v_qty, 'order', v_no);
  insert into order_status_events (order_id, status, created_by) values (v_id, 'created', 'web');

  -- server-side truth event (spec file 03 §6), tied to the browser session, no personal data
  if v_session is not null then
    insert into events (event_id, event_name, source, session_id, anonymous_id, consent_state, props, is_internal)
    values (gen_random_uuid(), 'order_created', 'server', v_session, v_anon, 'server',
            jsonb_build_object('order_no', v_no, 'colour', v_colour, 'qty', v_qty, 'value_paise', v_qty * 169000,
                               'pincode_prefix', left(v_pin, 3), 'state', v_state),
            v_test);
  end if;

  -- emails + WhatsApp ping; a failure here never loses the order
  begin perform notify_order(v_id); exception when others then raise warning 'notify_order %: %', v_no, sqlerrm; end;

  return jsonb_build_object('ok', true, 'order', v_no);
end $$;

-- ───────────────────────── Public: tell me when it's back ─────────────────────────
create or replace function notify_restock(p_colour text, p_phone text, p_session text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_phone text := right(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), 10);
begin
  if v_phone !~ '^[6-9][0-9]{9}$' then return jsonb_build_object('ok', false, 'error', 'phone'); end if;
  if not exists (select 1 from inventory where colour = lower(p_colour)) then
    return jsonb_build_object('ok', false, 'error', 'colour');
  end if;
  if not exists (select 1 from restock_requests where phone = v_phone and colour = lower(p_colour) and not notified) then
    insert into restock_requests (colour, phone, session_id) values (lower(p_colour), v_phone, left(p_session, 64));
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- ───────────────────────── Admin: order actions ─────────────────────────
-- order_action_core does the work; admin_order_action is the admin-only door to it.
-- (iThink tracking sync also uses the core, from a schedule with no one signed in.)
create or replace function order_action_core(p_order_no text, p_action text, p_reason text, p_courier text, p_awb text, p_who text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o orders; v_new text; v_who text := coalesce(p_who, 'admin'); v_restock boolean := false;
begin
  select * into o from orders where order_no = p_order_no for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'no_order'); end if;

  if p_action in ('no_answer', 'reschedule') then
    update orders set call_attempts = call_attempts + 1, last_call_outcome = p_action where order_id = o.order_id;
    insert into order_status_events (order_id, status, reason, attempt_no, created_by)
    values (o.order_id, 'call_attempted', p_action, o.call_attempts + 1, v_who);
    return jsonb_build_object('ok', true);
  elsif p_action = 'toggle_test' then
    update orders set is_test = not is_test where order_id = o.order_id;
    return jsonb_build_object('ok', true);
  end if;

  v_new := case p_action
    when 'confirm' then case when o.status = 'created' then 'confirmed' end
    when 'cancel'  then case when o.status in ('created', 'confirmed') then 'cancelled' end
    when 'ship'    then case when o.status in ('created', 'confirmed') then 'shipped' end
    when 'deliver' then case when o.status = 'shipped' then 'delivered' end
    when 'rto'     then case when o.status = 'shipped' then 'rto' end
    when 'return'  then case when o.status = 'delivered' then 'returned' end
    when 'unship'  then case when o.status = 'shipped' then 'confirmed' end   -- courier booking cancelled
  end;
  if v_new is null then return jsonb_build_object('ok', false, 'error', 'bad_transition', 'status', o.status); end if;

  update orders set status = v_new, status_updated_at = now(),
         call_attempts = call_attempts + case when p_action in ('confirm', 'cancel') and o.status = 'created' then 1 else 0 end,
         last_call_outcome = case when p_action in ('confirm', 'cancel') and o.status = 'created' then p_action else last_call_outcome end,
         courier = case when p_action = 'unship' then null else coalesce(nullif(p_courier, ''), courier) end,
         awb     = case when p_action = 'unship' then null else coalesce(nullif(p_awb, ''), awb) end
   where order_id = o.order_id;
  insert into order_status_events (order_id, status, reason, meta, created_by)
  values (o.order_id, v_new, coalesce(nullif(p_reason, ''), case when p_action = 'unship' then 'shipment_cancelled' end),
          case when p_action in ('ship', 'unship') then jsonb_build_object('courier', coalesce(p_courier, o.courier), 'awb', coalesce(p_awb, o.awb)) end, v_who);

  -- stock comes back when the camera does
  v_restock := v_new in ('cancelled', 'rto');
  if v_restock then
    update inventory set on_hand = on_hand + o.qty, updated_at = now() where colour = o.colour;
    insert into inventory_moves (colour, delta, reason, order_no, created_by)
    values (o.colour, o.qty, case when v_new = 'rto' then 'rto' else 'cancel' end, o.order_no, v_who);
  end if;

  insert into events (event_id, event_name, source, session_id, anonymous_id, consent_state, props, is_internal)
  values (gen_random_uuid(), case when p_action = 'unship' then 'order_ship_cancelled' else 'order_' || v_new end, 'server', coalesce(o.session_id, 'server'), o.anonymous_id, 'server',
          jsonb_build_object('order_no', o.order_no, 'reason', p_reason), o.is_test);
  return jsonb_build_object('ok', true, 'status', v_new, 'restocked', v_restock);
end $$;
revoke all on function order_action_core(text, text, text, text, text, text) from public, anon, authenticated;

create or replace function admin_order_action(p_order_no text, p_action text, p_reason text default null,
                                              p_courier text default null, p_awb text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not is_site_admin() then raise exception 'not allowed'; end if;
  return order_action_core(p_order_no, p_action, p_reason, p_courier, p_awb, coalesce(auth.jwt() ->> 'email', 'admin'));
end $$;

-- ───────────────────────── Admin: stock ─────────────────────────
create or replace function admin_stock(p_colour text, p_mode text, p_n int, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_old int; v_new int;
begin
  if not is_site_admin() then raise exception 'not allowed'; end if;
  select on_hand into v_old from inventory where colour = p_colour for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'colour'); end if;
  v_new := case p_mode when 'set' then p_n when 'add' then v_old + p_n end;
  if v_new is null or v_new < 0 then return jsonb_build_object('ok', false, 'error', 'bad_number'); end if;
  update inventory set on_hand = v_new, updated_at = now() where colour = p_colour;
  if v_new <> v_old then
    insert into inventory_moves (colour, delta, reason, note, created_by)
    values (p_colour, v_new - v_old, case p_mode when 'add' then 'restock' else 'adjust' end, nullif(p_note, ''),
            coalesce(auth.jwt() ->> 'email', 'admin'));
  end if;
  return jsonb_build_object('ok', true, 'on_hand', v_new);
end $$;

-- ───────────────────────── Admin: ad spend ─────────────────────────
create or replace function admin_set_spend(p_date date, p_rupees numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not is_site_admin() then raise exception 'not allowed'; end if;
  if p_rupees is null or p_rupees < 0 then return jsonb_build_object('ok', false); end if;
  insert into ad_spend_daily (date, spend_paise) values (p_date, round(p_rupees * 100))
  on conflict (date) do update set spend_paise = excluded.spend_paise, updated_at = now();
  return jsonb_build_object('ok', true);
end $$;

-- ───────────────────────── Admin: everything the dashboard shows ─────────────────────────
create or replace function admin_dashboard(p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  d int := p_to - p_from + 1;
  pf date := p_from - (p_to - p_from + 1);
  pt date := p_from - 1;
  result jsonb;
begin
  if not is_site_admin() then raise exception 'not allowed'; end if;

  with
  ss as (select * from sessions_v where not is_bot and not is_internal and started_date_ist between p_from and p_to),
  ps as (select * from sessions_v where not is_bot and not is_internal and started_date_ist between pf and pt),
  o  as (select * from orders where not is_test and (created_at at time zone 'Asia/Kolkata')::date between p_from and p_to),
  po as (select * from orders where not is_test and (created_at at time zone 'Asia/Kolkata')::date between pf and pt),
  ev as (select e.* from events e join ss using (session_id) where e.source = 'browser'),
  sp as (select coalesce(sum(spend_paise), 0) as spend from ad_spend_daily where date between p_from and p_to),
  faq_base as (
    select (select count(*) from ss where has_checkout) as n_ck,
           (select count(*) from ss where not has_checkout) as n_no
  ),
  last_section as (
    select distinct on (session_id) session_id, props ->> 'section_id' as section_id
    from ev where event_name = 'section_viewed'
    order by session_id, received_at desc
  )
  select jsonb_build_object(
    'range', jsonb_build_object('from', p_from, 'to', p_to, 'days', d),
    'kpi', jsonb_build_object(
      'sessions',          (select count(*) from ss),
      'visitors',          (select count(distinct anonymous_id) from ss),
      'engaged',           (select count(*) from ss where is_engaged),
      'bounces',           (select count(*) from ss where pageviews <= 1 and not is_engaged),
      'avg_engaged_s',     (select round(avg(engaged_ms) / 1000.0) from ss where engaged_ms > 0),
      'sessions_converted',(select count(*) from ss where has_order),
      'orders',            (select count(*) from o),
      'units',             (select coalesce(sum(qty), 0) from o),
      'gross_paise',       (select coalesce(sum(value_paise), 0) from o),
      'confirmed',         (select count(*) from o where status in ('confirmed','shipped','delivered','rto','returned')),
      'cancelled',         (select count(*) from o where status = 'cancelled'),
      'shipped',           (select count(*) from o where status in ('shipped','delivered','rto','returned')),
      'delivered',         (select count(*) from o where status in ('delivered','returned')),
      'rto',               (select count(*) from o where status = 'rto'),
      'delivered_paise',   (select coalesce(sum(value_paise), 0) from o where status = 'delivered'),
      'to_call',           (select count(*) from orders where not is_test and status = 'created'),
      'spend_paise',       (select spend from sp),
      'consented',         (select count(*) from ss where consent_state <> 'none')
    ),
    'prev', jsonb_build_object(
      'sessions',          (select count(*) from ps),
      'sessions_converted',(select count(*) from ps where has_order),
      'orders',            (select count(*) from po),
      'delivered',         (select count(*) from po where status in ('delivered','returned'))
    ),
    'live', (select count(distinct session_id) from events
             where received_at > now() - interval '5 minutes' and not is_bot and not is_internal and source = 'browser'),
    'daily', (select coalesce(jsonb_agg(x order by x.day), '[]'::jsonb) from (
               select g::date as day,
                      (select count(*) from ss where started_date_ist = g::date) as sessions,
                      (select count(*) from o where (created_at at time zone 'Asia/Kolkata')::date = g::date) as orders
               from generate_series(p_from, p_to, interval '1 day') g) x),
    'funnel', jsonb_build_array(
      jsonb_build_object('step', 'Sessions',           'n', (select count(*) from ss)),
      jsonb_build_object('step', 'Saw the colours',    'n', (select count(*) from ss where has_product_view)),
      jsonb_build_object('step', 'Opened order form',  'n', (select count(*) from ss where has_checkout)),
      jsonb_build_object('step', 'Ordered',            'n', (select count(*) from ss where has_order)),
      jsonb_build_object('step', 'Confirmed on call',  'n', (select count(*) from o where status in ('confirmed','shipped','delivered','rto','returned'))),
      jsonb_build_object('step', 'Shipped',            'n', (select count(*) from o where status in ('shipped','delivered','rto','returned'))),
      jsonb_build_object('step', 'Delivered',          'n', (select count(*) from o where status in ('delivered','returned')))
    ),
    'channels', (select coalesce(jsonb_agg(c order by c.sessions desc), '[]'::jsonb) from (
                 select channel, count(*) as sessions, count(*) filter (where is_engaged) as engaged,
                        count(*) filter (where has_checkout) as checkouts, count(*) filter (where has_order) as converted
                 from ss group by channel) c),
    'campaigns', (select coalesce(jsonb_agg(c order by c.sessions desc), '[]'::jsonb) from (
                  select coalesce(attr ->> 'utm_campaign', '—') as campaign, coalesce(attr ->> 'utm_content', '—') as ad,
                         count(*) as sessions, count(*) filter (where is_bounce_like) as bounces,
                         count(*) filter (where has_checkout) as checkouts, count(*) filter (where has_order) as converted
                  from (select *, (pageviews <= 1 and not is_engaged) as is_bounce_like from ss) z
                  where attr ? 'utm_campaign' or attr ? 'utm_content'
                  group by 1, 2 order by 3 desc limit 25) c),
    'devices', (select coalesce(jsonb_agg(c order by c.sessions desc), '[]'::jsonb) from (
                select coalesce(device_type, 'unknown') as device, count(*) as sessions,
                       count(*) filter (where has_order) as converted from ss group by 1) c),
    'colours', (select coalesce(jsonb_agg(c order by c.sort), '[]'::jsonb) from (
                select i.colour, i.sort, i.on_hand, i.low_at,
                       (select count(distinct session_id) from ev where event_name = 'colour_swatch_selected' and props ->> 'to_colour' = i.colour) as picked,
                       (select count(distinct session_id) from ev where event_name = 'checkout_started' and props ->> 'colour' = i.colour) as checkouts,
                       (select count(*) from o where o.colour = i.colour) as orders,
                       (select coalesce(sum(qty), 0) from o where o.colour = i.colour) as units,
                       (select count(*) from o where o.colour = i.colour and status in ('delivered','returned')) as delivered,
                       (select count(*) from o where o.colour = i.colour and status = 'rto') as rto,
                       (select count(*) from restock_requests r where r.colour = i.colour and not r.notified) as waiting
                from inventory i) c),
    'sections', (select coalesce(jsonb_agg(c order by c.reached desc), '[]'::jsonb) from (
                 select props ->> 'section_id' as section, count(distinct session_id) as reached,
                        count(distinct session_id) filter (where session_id in (select session_id from ss where has_checkout)) as reached_ck
                 from ev where event_name = 'section_viewed' group by 1) c),
    'exit_sections', (select coalesce(jsonb_agg(c order by c.n desc), '[]'::jsonb) from (
                      select l.section_id as section, count(*) as n from last_section l
                      join ss on ss.session_id = l.session_id where not ss.has_checkout
                      group by 1 order by 2 desc limit 8) c),
    'faq', (select coalesce(jsonb_agg(c order by c.sessions desc), '[]'::jsonb) from (
            select props ->> 'faq_id' as faq, count(distinct ev.session_id) as sessions,
                   round(
                     (count(distinct ev.session_id) filter (where not s.has_checkout)::numeric / nullif((select n_no from faq_base), 0))
                     / nullif(count(distinct ev.session_id) filter (where s.has_checkout)::numeric / nullif((select n_ck from faq_base), 0), 0)
                   , 2) as lift
            from ev join ss s using (session_id) where event_name = 'faq_opened' group by 1) c),
    'looks', (select coalesce(jsonb_agg(c order by c.n desc), '[]'::jsonb) from (
              select props ->> 'look' as look, count(*) as n from ev where event_name = 'look_selected' group by 1) c),
    'app_tabs', (select coalesce(jsonb_agg(c order by c.n desc), '[]'::jsonb) from (
                 select props ->> 'usecase' as usecase, count(*) as n from ev where event_name = 'app_usecase_selected' group by 1) c),
    'field_errors', (select coalesce(jsonb_agg(c order by c.n desc), '[]'::jsonb) from (
                     select props ->> 'field' as field, props ->> 'error_type' as error_type, count(*) as n
                     from ev where event_name = 'checkout_field_error' group by 1, 2 order by 3 desc limit 10) c),
    'abandoned', (select count(*) from ev where event_name = 'form_abandoned'),
    'frustration', (select coalesce(jsonb_agg(c order by c.n desc), '[]'::jsonb) from (
                    select event_name as kind, coalesce(props ->> 'selector', props ->> 'message') as what, count(*) as n
                    from ev where event_name in ('rage_click', 'dead_click', 'js_error', 'api_error')
                    group by 1, 2 order by 3 desc limit 12) c),
    'scroll', (select coalesce(jsonb_agg(c order by c.depth), '[]'::jsonb) from (
               select (props ->> 'depth_pct')::int as depth, count(distinct session_id) as sessions
               from ev where event_name = 'scroll_depth_reached' group by 1) c),
    'speed', (select jsonb_build_object(
                'lcp_p75_ms', percentile_cont(0.75) within group (order by (props ->> 'lcp_ms')::numeric),
                'cls_p75',    percentile_cont(0.75) within group (order by (props ->> 'cls')::numeric),
                'n', count(*))
              from ev where event_name = 'web_vitals_reported' and props ? 'lcp_ms'),
    'states', (select coalesce(jsonb_agg(c order by c.orders desc), '[]'::jsonb) from (
               select state, count(*) as orders, count(*) filter (where status = 'rto') as rto from o group by 1) c),
    'cancel_reasons', (select coalesce(jsonb_agg(c order by c.n desc), '[]'::jsonb) from (
                       select coalesce(se.reason, 'none') as reason, se.status, count(*) as n
                       from order_status_events se join o on o.order_id = se.order_id
                       where se.status in ('cancelled', 'rto') group by 1, 2) c),
    'health', jsonb_build_object(
      'events_24h',   (select count(*) from events where received_at > now() - interval '24 hours'),
      'rejected_24h', (select coalesce(jsonb_object_agg(reason, n), '{}'::jsonb) from (
                         select reason, count(*) as n from events_rejected
                         where received_at > now() - interval '24 hours' group by 1) r),
      'browser_orders', (select count(*) from ev where event_name = 'order_placed'),
      'server_orders',  (select count(*) from o)
    )
  ) into result;
  return result;
end $$;

-- ───────────────────────── Admin: order list ─────────────────────────
create or replace function admin_orders(p_status text default null, p_limit int default 200) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_site_admin() then raise exception 'not allowed'; end if;
  return (select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) from (
    select order_no, created_at, name, phone, email, address, city, state, pincode, note, colour, qty, value_paise,
           status, call_attempts, last_call_outcome, courier, awb, channel, device_type, is_test,
           ship_via, tracking_url, track_status, track_code, track_where, track_at, edd
    from orders
    where p_status is null
       or (p_status = 'open' and status in ('created', 'confirmed', 'shipped'))
       or status = p_status
    order by created_at desc limit least(p_limit, 500)) x);
end $$;

create or replace function admin_stock_view() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_site_admin() then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'stock', (select jsonb_agg(i order by i.sort) from (
                select colour, on_hand, low_at, sort, updated_at,
                       (select count(*) from restock_requests r where r.colour = inventory.colour and not r.notified) as waiting,
                       (select coalesce(sum(qty), 0) from orders o where o.colour = inventory.colour and o.status in ('created', 'confirmed') and not o.is_test) as to_ship
                from inventory) i),
    'moves', (select coalesce(jsonb_agg(m order by m.created_at desc), '[]'::jsonb) from (
                select colour, delta, reason, order_no, note, created_at, created_by
                from inventory_moves order by created_at desc limit 40) m),
    'waiting', (select coalesce(jsonb_agg(r order by r.created_at), '[]'::jsonb) from (
                select id, colour, phone, created_at from restock_requests where not notified) r),
    'spend', (select coalesce(jsonb_agg(s order by s.date desc), '[]'::jsonb) from (
                select date, spend_paise from ad_spend_daily order by date desc limit 14) s)
  );
end $$;

create or replace function admin_restock_notified(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not is_site_admin() then raise exception 'not allowed'; end if;
  update restock_requests set notified = true where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- ════════════════════════════════════════════════════════════════════════════
-- Shipping with iThink Logistics (API v3, docs.ithinklogistics.com)
--   /admin → Orders → "Ship via iThink" books the courier and gets the AWB,
--   "Label" opens the PDF, "Cancel shipment" undoes a booking before pickup,
--   "Refresh tracking" (or the optional 3-hourly schedule, SETUP.md step 9) marks
--   orders Delivered / RTO by itself. RTO puts the stock back.
-- Keys live in Vault: ithink_access_token, ithink_secret_key (iThink panel → Settings → API).
-- Postgres calls iThink itself (the http extension), so the keys never reach a browser.
-- ════════════════════════════════════════════════════════════════════════════
create extension if not exists http with schema extensions;

alter table orders add column if not exists ship_via     text;         -- 'ithink' when booked from /admin
alter table orders add column if not exists ship_ref     text;         -- iThink refnum
alter table orders add column if not exists tracking_url text;
alter table orders add column if not exists track_status text;         -- iThink current_status, e.g. In Transit
alter table orders add column if not exists track_code   text;         -- UD / DL / CN / RT …
alter table orders add column if not exists track_where  text;         -- last scan location
alter table orders add column if not exists track_at     timestamptz;  -- when we last asked
alter table orders add column if not exists edd          text;         -- expected delivery date, as iThink sends it
create index if not exists orders_awb_idx on orders (awb);

create table if not exists ship_settings (
  id         int primary key default 1 check (id = 1),
  mode       text not null default 'live' check (mode in ('live', 'test')),   -- test = pre-alpha.ithinklogistics.com
  pickup_id  text,                     -- iThink warehouse id you ship from
  return_id  text,                     -- iThink warehouse id RTOs go back to (usually the same)
  courier    text not null default '', -- '' = iThink's own courier priority; or delhivery, xpressbees, ekart, bluedart, ecom
  service    text not null default '', -- s_type: '' / surface / air
  length_cm  numeric not null default 12,
  width_cm   numeric not null default 10,
  height_cm  numeric not null default 8,
  weight_kg  numeric not null default 0.3,   -- per camera, boxed
  hsn        text not null default '',
  gst        text not null default '',
  label_size text not null default 'A4' check (label_size in ('A4', 'A5', 'A6')),
  updated_at timestamptz not null default now()
);
insert into ship_settings (id) values (1) on conflict do nothing;
alter table ship_settings enable row level security;

-- every call to iThink and its answer (keys are never stored here)
create table if not exists ithink_log (
  id          bigserial primary key,
  created_at  timestamptz not null default now(),
  order_no    text,
  path        text not null,
  request     jsonb,
  http_status int,
  response    jsonb
);
alter table ithink_log enable row level security;

-- one address into up to 3 lines of ~n characters, split on spaces (couriers cut long lines)
create or replace function split_addr(t text, n int default 100) returns text[]
language plpgsql immutable as $$
declare out text[] := '{}'; cur text := ''; w text;
begin
  foreach w in array regexp_split_to_array(btrim(coalesce(t, '')), '\s+') loop
    if cur <> '' and length(cur) + 1 + length(w) > n and coalesce(array_length(out, 1), 0) < 2 then
      out := out || cur; cur := w;
    else
      cur := btrim(cur || ' ' || w);
    end if;
  end loop;
  return out || cur;
end $$;

-- POST {"data": {...p_data, access_token, secret_key}} to iThink. Returns {ok, http, body} or {ok:false, error}.
create or replace function ithink_call(p_path text, p_data jsonb, p_order_no text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s ship_settings; v_tok text := secret('ithink_access_token'); v_sec text := secret('ithink_secret_key');
  v_host text; r extensions.http_response; v_body jsonb;
begin
  select * into s from ship_settings where id = 1;
  if v_tok is null or v_sec is null then
    return jsonb_build_object('ok', false, 'error', 'iThink keys are not in Supabase Vault yet (SETUP.md step 9).');
  end if;
  v_host := case when s.mode = 'test' then 'https://pre-alpha.ithinklogistics.com'
                 when p_path like 'order/track%' then 'https://api.ithinklogistics.com'
                 else 'https://my.ithinklogistics.com' end;
  perform set_config('http.timeout_msec', '20000', true);
  begin
    r := extensions.http_post(v_host || '/api_v3/' || p_path,
           jsonb_build_object('data', p_data || jsonb_build_object('access_token', v_tok, 'secret_key', v_sec))::text,
           'application/json');
  exception when others then
    insert into ithink_log (order_no, path, request, response) values (p_order_no, p_path, p_data, to_jsonb(sqlerrm));
    return jsonb_build_object('ok', false, 'error', 'Could not reach iThink: ' || sqlerrm);
  end;
  begin v_body := r.content::jsonb; exception when others then v_body := to_jsonb(left(r.content, 2000)); end;
  insert into ithink_log (order_no, path, request, http_status, response) values (p_order_no, p_path, p_data, r.status, v_body);
  return jsonb_build_object('ok', r.status between 200 and 299, 'http', r.status, 'body', v_body,
                            'error', case when r.status not between 200 and 299 then 'iThink answered HTTP ' || r.status end);
end $$;

-- best readable error out of an iThink answer
create or replace function ithink_err(res jsonb) returns text language sql immutable as $$
  select coalesce(nullif(res -> 'body' -> 'data' -> '1' ->> 'remark', ''), nullif(res -> 'body' ->> 'html_message', ''),
                  nullif(res -> 'body' ->> 'message', ''), res ->> 'error', left((res -> 'body')::text, 300), 'iThink did not answer');
$$;

-- "Your Glimp is on its way" email to the buyer (Resend, same as the order email)
create or replace function notify_shipped(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare o orders; v_key text := secret('resend_api_key'); v_first text; v_total text; v_track text; v_html text; v_text text;
begin
  select * into o from orders where order_id = p_id;
  if not found or o.email is null or v_key is null then return; end if;
  v_first := initcap(split_part(o.name, ' ', 1));
  v_total := '₹' || to_char(o.value_paise / 100, 'FM999,999');
  v_track := coalesce(o.tracking_url, '');
  v_html := format($h$<div style="background:#f2efe8;padding:24px 12px;font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1c1a17">
<div style="max-width:560px;margin:0 auto;background:#ffffff;border-radius:16px;padding:24px;font-size:16px;line-height:1.6">
<p style="margin:0 0 16px">Hi %s,</p>
<p style="margin:0 0 16px">Your Glimp is on its way.</p>
<p style="margin:0 0 16px;font-size:14px"><span style="color:#6b6760">Order</span> %s<br><span style="color:#6b6760">Courier</span> %s<br><span style="color:#6b6760">AWB</span> %s<br><span style="color:#6b6760">Pay on delivery</span> <b>%s</b></p>
%s
<p style="margin:0">Yash<br><span style="color:#6b6760">Founder, Glimp</span></p>
</div>
<p style="text-align:center;font-size:12px;color:#6b6760;margin:16px 0 0"><a href="https://glimp.in" style="color:#6b6760">glimp.in</a></p>
</div>$h$, html_esc(v_first), o.order_no, html_esc(coalesce(o.courier, '')), html_esc(coalesce(o.awb, '')), v_total,
    case when v_track <> '' then format('<p style="margin:0 0 20px"><a href="%s" style="display:inline-block;padding:10px 18px;border-radius:999px;background:#1c1a17;color:#ffffff;text-decoration:none;font-weight:600">Track</a></p>', html_esc(v_track)) else '' end);
  v_text := format(E'Hi %s,\n\nYour Glimp is on its way.\n\nOrder %s\nCourier %s\nAWB %s\nPay on delivery %s\n%s\nYash\nFounder, Glimp',
                   v_first, o.order_no, coalesce(o.courier, ''), coalesce(o.awb, ''), v_total,
                   case when v_track <> '' then E'\nTrack: ' || v_track || E'\n' else '' end);
  perform net.http_post(
    url := 'https://api.resend.com/emails',
    headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
    body := jsonb_build_object('from', 'Yash from Glimp <yash@glimp.in>', 'to', jsonb_build_array(o.email), 'reply_to', 'yash@glimp.in',
                               'subject', case when o.is_test then '[test] ' else '' end || 'Your Glimp is on its way · ' || o.order_no,
                               'html', v_html, 'text', v_text));
end $$;

-- Book the courier for one order. Marks it Shipped with the AWB iThink gives back.
create or replace function admin_ithink_ship(p_order_no text) returns jsonb
language plpgsql security definer set search_path = public set statement_timeout = '40s' as $$
declare
  o orders; s ship_settings; a text[]; v_total numeric; v_cod boolean; v_ship jsonb; res jsonb; d jsonb; v_awb text; r jsonb;
begin
  if not is_site_admin() then raise exception 'not allowed'; end if;
  select * into s from ship_settings where id = 1;
  if coalesce(s.pickup_id, '') = '' or coalesce(s.return_id, '') = '' then
    return jsonb_build_object('ok', false, 'error', 'Add the pickup and return IDs on Stock → iThink first.');
  end if;
  select * into o from orders where order_no = p_order_no for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'no_order'); end if;
  if o.status not in ('created', 'confirmed') then
    return jsonb_build_object('ok', false, 'error', 'bad_transition', 'status', o.status);
  end if;
  if o.is_test and s.mode = 'live' then
    return jsonb_build_object('ok', false, 'error', 'This is a test order. Mark it "Not a test" or switch iThink to Test mode.');
  end if;

  a := split_addr(o.address, 100);
  v_total := o.value_paise / 100.0;
  v_cod := o.payment_method = 'cod';
  v_ship := jsonb_build_object(
      'waybill', '', 'order', o.order_no, 'sub_order', '',
      'order_date', to_char(o.created_at at time zone 'Asia/Kolkata', 'DD-MM-YYYY'),
      'total_amount', v_total, 'name', o.name, 'company_name', '',
      'add', a[1], 'add2', coalesce(a[2], ''), 'add3', coalesce(a[3], ''),
      'pin', o.pincode, 'city', o.city, 'state', o.state, 'country', 'India',
      'phone', o.phone, 'alt_phone', '', 'email', coalesce(o.email, ''),
      'is_billing_same_as_shipping', 'yes')
    || jsonb_build_object(
      'billing_name', o.name, 'billing_company_name', '',
      'billing_add', a[1], 'billing_add2', coalesce(a[2], ''), 'billing_add3', coalesce(a[3], ''),
      'billing_pin', o.pincode, 'billing_city', o.city, 'billing_state', o.state, 'billing_country', 'India',
      'billing_phone', o.phone, 'billing_alt_phone', '', 'billing_email', coalesce(o.email, ''))
    || jsonb_build_object(
      'products', jsonb_build_array(jsonb_build_object(
          'product_name', 'Glimp keychain camera - ' || initcap(o.colour), 'product_sku', 'GLIMP-' || upper(o.colour),
          'product_quantity', o.qty, 'product_price', round(v_total / o.qty, 2), 'product_tax_rate', '',
          'product_hsn_code', s.hsn, 'product_discount', 0)),
      'shipment_length', s.length_cm, 'shipment_width', s.width_cm, 'shipment_height', s.height_cm,
      'weight', round(s.weight_kg * o.qty, 3),
      'shipping_charges', 0, 'giftwrap_charges', 0, 'transaction_charges', 0, 'total_discount', 0,
      'first_attemp_discount', 0, 'cod_charges', 0, 'advance_amount', 0,
      'cod_amount', case when v_cod then v_total else 0 end, 'payment_mode', case when v_cod then 'COD' else 'Prepaid' end,
      'reseller_name', '', 'eway_bill_number', '', 'gst_number', s.gst, 'return_address_id', s.return_id);

  res := ithink_call('order/add.json',
           jsonb_build_object('shipments', jsonb_build_array(v_ship), 'pickup_address_id', s.pickup_id,
                              'logistics', s.courier, 's_type', s.service, 'order_type', 'forward'),
           o.order_no);
  d := res -> 'body' -> 'data' -> '1';
  v_awb := nullif(btrim(coalesce(d ->> 'waybill', '')), '');
  if v_awb is null then return jsonb_build_object('ok', false, 'error', ithink_err(res)); end if;

  r := order_action_core(o.order_no, 'ship', null, coalesce(nullif(d ->> 'logistic_name', ''), 'iThink'), v_awb,
                         coalesce(auth.jwt() ->> 'email', 'admin'));
  update orders set ship_via = 'ithink', ship_ref = nullif(d ->> 'refnum', ''), tracking_url = nullif(d ->> 'tracking_url', ''),
                    track_status = 'Manifested', track_code = null, track_where = null, track_at = now(), edd = null
   where order_id = o.order_id;
  begin perform notify_shipped(o.order_id); exception when others then raise warning 'notify_shipped %: %', o.order_no, sqlerrm; end;
  return jsonb_build_object('ok', true, 'awb', v_awb, 'courier', d ->> 'logistic_name', 'tracking_url', d ->> 'tracking_url');
end $$;

-- Shipping label PDF for one or more orders (iThink hosts the file; we hand back its link)
create or replace function admin_ithink_label(p_order_nos text[]) returns jsonb
language plpgsql security definer set search_path = public set statement_timeout = '40s' as $$
declare s ship_settings; v_awbs text; res jsonb; v_url text;
begin
  if not is_site_admin() then raise exception 'not allowed'; end if;
  select * into s from ship_settings where id = 1;
  select string_agg(awb, ',') into v_awbs from orders
   where order_no = any (p_order_nos) and ship_via = 'ithink' and awb is not null and status = 'shipped';
  if v_awbs is null then return jsonb_build_object('ok', false, 'error', 'No iThink shipments here.'); end if;
  res := ithink_call('shipping/label.json',
           jsonb_build_object('awb_numbers', v_awbs, 'page_size', s.label_size,
                              'display_cod_prepaid', '', 'display_shipper_mobile', '', 'display_shipper_address', ''));
  v_url := nullif(res -> 'body' ->> 'file_name', '');
  if v_url is null then return jsonb_build_object('ok', false, 'error', ithink_err(res)); end if;
  return jsonb_build_object('ok', true, 'url', v_url);
end $$;

-- Cancel the courier booking (before pickup). The order goes back to "To ship".
create or replace function admin_ithink_cancel(p_order_no text) returns jsonb
language plpgsql security definer set search_path = public set statement_timeout = '40s' as $$
declare o orders; res jsonb; d jsonb; v_ok boolean;
begin
  if not is_site_admin() then raise exception 'not allowed'; end if;
  select * into o from orders where order_no = p_order_no for update;
  if not found or o.status <> 'shipped' or o.ship_via is distinct from 'ithink' or o.awb is null then
    return jsonb_build_object('ok', false, 'error', 'Not an iThink shipment.');
  end if;
  res := ithink_call('order/cancel.json', jsonb_build_object('awb_numbers', o.awb), o.order_no);
  d := res -> 'body' -> 'data' -> '1';
  v_ok := coalesce((res ->> 'ok')::boolean, false) and lower(coalesce(d ->> 'status', res -> 'body' ->> 'status', '')) = 'success';
  if not v_ok then return jsonb_build_object('ok', false, 'error', ithink_err(res)); end if;
  perform order_action_core(o.order_no, 'unship', null, null, null, coalesce(auth.jwt() ->> 'email', 'admin'));
  update orders set ship_via = null, ship_ref = null, tracking_url = null, track_status = null, track_code = null,
                    track_where = null, track_at = null, edd = null
   where order_id = o.order_id;
  return jsonb_build_object('ok', true);
end $$;

-- Ask iThink where every shipped order is (10 AWBs per call). Delivered → Delivered, RTO Delivered → RTO
-- (stock back), Cancelled at iThink → back to "To ship". Runs from /admin or from the schedule.
create or replace function ithink_sync(p_max int default 100) returns jsonb
language plpgsql security definer set search_path = public set statement_timeout = '170s' as $$
declare
  v_awbs text[]; v_batch text[]; i int; res jsonb; k text; t jsonb; v_cur text; v_no text; v_reason text;
  n_checked int := 0; n_deliv int := 0; n_rto int := 0; v_err text;
begin
  select array_agg(awb) into v_awbs from (
    select awb from orders where status = 'shipped' and ship_via = 'ithink' and awb is not null
    order by track_at nulls first limit p_max) x;
  if v_awbs is null then return jsonb_build_object('ok', true, 'checked', 0, 'delivered', 0, 'rto', 0); end if;

  for i in 1 .. array_length(v_awbs, 1) by 10 loop
    v_batch := v_awbs[i : i + 9];
    res := ithink_call('order/track.json', jsonb_build_object('awb_number_list', array_to_string(v_batch, ',')));
    if not coalesce((res ->> 'ok')::boolean, false) or jsonb_typeof(res -> 'body' -> 'data') is distinct from 'object' then
      v_err := ithink_err(res); continue;
    end if;
    for k, t in select key, value from jsonb_each(res -> 'body' -> 'data') loop
      if jsonb_typeof(t) <> 'object' or coalesce(t ->> 'current_status', '') = '' then continue; end if;
      v_cur := btrim(t ->> 'current_status');
      v_no := null;
      update orders set track_status = left(v_cur, 60), track_code = left(nullif(t ->> 'current_status_code', ''), 20),
                        track_where = left(nullif(t -> 'last_scan_details' ->> 'scan_location', ''), 80),
                        track_at = now(), edd = left(nullif(t ->> 'expected_delivery_date', ''), 30)
       where awb = coalesce(nullif(t ->> 'awb_no', ''), k) and status = 'shipped' and ship_via = 'ithink'
       returning order_no into v_no;
      if v_no is null then continue; end if;
      n_checked := n_checked + 1;
      if lower(v_cur) = 'delivered' then
        perform order_action_core(v_no, 'deliver', null, null, null, 'ithink'); n_deliv := n_deliv + 1;
      elsif lower(v_cur) = 'rto delivered' then
        v_reason := lower(coalesce(t -> 'last_scan_details' ->> 'reason', ''));
        v_reason := case when v_reason ~ 'refus|cancel|not interested|reject' then 'refused'
                         when v_reason ~ 'address|incomplete|wrong' then 'wrong_address'
                         when v_reason ~ 'not available|unreachable|not reachable|not contactable|door' then 'unreachable'
                         else 'other' end;
        perform order_action_core(v_no, 'rto', v_reason, null, null, 'ithink'); n_rto := n_rto + 1;
      elsif lower(v_cur) = 'cancelled' then
        perform order_action_core(v_no, 'unship', null, null, null, 'ithink');
        update orders set ship_via = null, ship_ref = null, tracking_url = null where order_no = v_no;
      end if;
    end loop;
  end loop;
  return jsonb_build_object('ok', v_err is null or n_checked > 0, 'checked', n_checked, 'delivered', n_deliv, 'rto', n_rto, 'error', v_err);
end $$;

create or replace function admin_ithink_track() returns jsonb
language plpgsql security definer set search_path = public set statement_timeout = '170s' as $$
begin
  if not is_site_admin() then raise exception 'not allowed'; end if;
  return ithink_sync(100);
end $$;

-- Your iThink warehouses (their ids are the pickup / return IDs). Also proves the keys work.
create or replace function admin_ithink_warehouses() returns jsonb
language plpgsql security definer set search_path = public set statement_timeout = '40s' as $$
declare res jsonb;
begin
  if not is_site_admin() then raise exception 'not allowed'; end if;
  res := ithink_call('warehouse/get.json', '{}'::jsonb);
  if jsonb_typeof(res -> 'body' -> 'data') is distinct from 'array' then
    return jsonb_build_object('ok', false, 'error', ithink_err(res));
  end if;
  return jsonb_build_object('ok', true, 'warehouses', (
    select coalesce(jsonb_agg(jsonb_build_object('id', w ->> 'id', 'name', w ->> 'company_name',
             'address', concat_ws(', ', nullif(w ->> 'address1', ''), nullif(w ->> 'city_name', ''), nullif(w ->> 'pincode', '')),
             'status', w ->> 'status')), '[]'::jsonb)
    from jsonb_array_elements(res -> 'body' -> 'data') w));
end $$;

create or replace function admin_ship_settings() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_site_admin() then raise exception 'not allowed'; end if;
  return (select to_jsonb(s) - 'id' from ship_settings s where id = 1)
         || jsonb_build_object('has_keys', secret('ithink_access_token') is not null and secret('ithink_secret_key') is not null);
end $$;

create or replace function admin_ship_settings_save(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not is_site_admin() then raise exception 'not allowed'; end if;
  update ship_settings set
    mode       = case when p ->> 'mode' in ('live', 'test') then p ->> 'mode' else mode end,
    pickup_id  = nullif(btrim(coalesce(p ->> 'pickup_id', pickup_id)), ''),
    return_id  = nullif(btrim(coalesce(p ->> 'return_id', return_id)), ''),
    courier    = lower(btrim(coalesce(p ->> 'courier', courier))),
    service    = lower(btrim(coalesce(p ->> 'service', service))),
    length_cm  = coalesce(nullif(p ->> 'length_cm', '')::numeric, length_cm),
    width_cm   = coalesce(nullif(p ->> 'width_cm', '')::numeric, width_cm),
    height_cm  = coalesce(nullif(p ->> 'height_cm', '')::numeric, height_cm),
    weight_kg  = coalesce(nullif(p ->> 'weight_kg', '')::numeric, weight_kg),
    hsn        = btrim(coalesce(p ->> 'hsn', hsn)),
    gst        = upper(btrim(coalesce(p ->> 'gst', gst))),
    label_size = case when p ->> 'label_size' in ('A4', 'A5', 'A6') then p ->> 'label_size' else label_size end,
    updated_at = now()
  where id = 1;
  return jsonb_build_object('ok', true);
end $$;

-- ───────────────────────── Who may call what ─────────────────────────
-- Only this file's functions are touched; the app's own functions keep their grants.
revoke execute on function
  is_site_admin(), allowed_events(), essential_events(), channel_of(jsonb),
  ingest(jsonb), place_order(jsonb), get_stock(), notify_restock(text, text, text),
  admin_order_action(text, text, text, text, text), admin_stock(text, text, int, text),
  admin_set_spend(date, numeric), admin_dashboard(date, date), admin_orders(text, int),
  admin_stock_view(), admin_restock_notified(bigint), html_esc(text), url_encode(text),
  split_addr(text, int), ithink_call(text, jsonb, text), ithink_err(jsonb), notify_shipped(uuid), ithink_sync(int),
  admin_ithink_ship(text), admin_ithink_label(text[]), admin_ithink_cancel(text), admin_ithink_track(),
  admin_ithink_warehouses(), admin_ship_settings(), admin_ship_settings_save(jsonb)
  from public, anon, authenticated;
grant execute on function ingest(jsonb), place_order(jsonb), get_stock(), notify_restock(text, text, text)
  to anon, authenticated;
grant execute on function is_site_admin(), admin_dashboard(date, date), admin_orders(text, int),
  admin_order_action(text, text, text, text, text), admin_stock(text, text, int, text),
  admin_set_spend(date, numeric), admin_stock_view(), admin_restock_notified(bigint),
  admin_ithink_ship(text), admin_ithink_label(text[]), admin_ithink_cancel(text), admin_ithink_track(),
  admin_ithink_warehouses(), admin_ship_settings(), admin_ship_settings_save(jsonb)
  to authenticated;
-- Every admin_* function also checks is_site_admin() itself, so a signed-in app user gets "not allowed".

-- ───────────────────────── Last step: make yourself admin ─────────────────────────
-- Replace with the email you'll sign in with on glimp.in/admin, then run just this line:
-- insert into site_admins (email) values ('you@example.com') on conflict do nothing;
