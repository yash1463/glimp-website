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
  ('black', 10, 1), ('white', 10, 2), ('red', 10, 3), ('yellow', 10, 4),
  ('blue', 10, 5), ('lime', 10, 6), ('teal', 10, 7), ('grey', 10, 8)
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
  select coalesce(jsonb_object_agg(colour, jsonb_build_object(
           'status', case when on_hand <= 0 then 'out' when on_hand <= low_at then 'low' else 'in' end,
           'left',   case when on_hand between 1 and low_at then on_hand end)), '{}'::jsonb)
  from inventory;
$$;

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

  insert into orders (order_no, name, phone, address, city, state, pincode, note, colour, qty, value_paise,
                      session_id, anonymous_id, attr, channel, device_type, is_test)
  values (v_no, v_name, v_phone, v_address, v_city, v_state, v_pin, v_note, v_colour, v_qty, v_qty * 149000,
          v_session, v_anon, v_attr, channel_of(v_attr), left(p ->> 'device_type', 12), v_test)
  returning order_id into v_id;

  insert into inventory_moves (colour, delta, reason, order_no) values (v_colour, -v_qty, 'order', v_no);
  insert into order_status_events (order_id, status, created_by) values (v_id, 'created', 'web');

  -- server-side truth event (spec file 03 §6), tied to the browser session, no personal data
  if v_session is not null then
    insert into events (event_id, event_name, source, session_id, anonymous_id, consent_state, props, is_internal)
    values (gen_random_uuid(), 'order_created', 'server', v_session, v_anon, 'server',
            jsonb_build_object('order_no', v_no, 'colour', v_colour, 'qty', v_qty, 'value_paise', v_qty * 149000,
                               'pincode_prefix', left(v_pin, 3), 'state', v_state),
            v_test);
  end if;

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
create or replace function admin_order_action(p_order_no text, p_action text, p_reason text default null,
                                              p_courier text default null, p_awb text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o orders; v_new text; v_who text := coalesce(auth.jwt() ->> 'email', 'admin'); v_restock boolean := false;
begin
  if not is_site_admin() then raise exception 'not allowed'; end if;
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
  end;
  if v_new is null then return jsonb_build_object('ok', false, 'error', 'bad_transition', 'status', o.status); end if;

  update orders set status = v_new, status_updated_at = now(),
         call_attempts = call_attempts + case when p_action in ('confirm', 'cancel') and o.status = 'created' then 1 else 0 end,
         last_call_outcome = case when p_action in ('confirm', 'cancel') and o.status = 'created' then p_action else last_call_outcome end,
         courier = coalesce(nullif(p_courier, ''), courier), awb = coalesce(nullif(p_awb, ''), awb)
   where order_id = o.order_id;
  insert into order_status_events (order_id, status, reason, meta, created_by)
  values (o.order_id, v_new, nullif(p_reason, ''),
          case when p_action = 'ship' then jsonb_build_object('courier', p_courier, 'awb', p_awb) end, v_who);

  -- stock comes back when the camera does
  v_restock := v_new in ('cancelled', 'rto');
  if v_restock then
    update inventory set on_hand = on_hand + o.qty, updated_at = now() where colour = o.colour;
    insert into inventory_moves (colour, delta, reason, order_no, created_by)
    values (o.colour, o.qty, case when v_new = 'rto' then 'rto' else 'cancel' end, o.order_no, v_who);
  end if;

  insert into events (event_id, event_name, source, session_id, anonymous_id, consent_state, props, is_internal)
  values (gen_random_uuid(), 'order_' || v_new, 'server', coalesce(o.session_id, 'server'), o.anonymous_id, 'server',
          jsonb_build_object('order_no', o.order_no, 'reason', p_reason), o.is_test);
  return jsonb_build_object('ok', true, 'status', v_new, 'restocked', v_restock);
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
    select order_no, created_at, name, phone, address, city, state, pincode, note, colour, qty, value_paise,
           status, call_attempts, last_call_outcome, courier, awb, channel, device_type, is_test
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

-- ───────────────────────── Who may call what ─────────────────────────
-- Only this file's functions are touched; the app's own functions keep their grants.
revoke execute on function
  is_site_admin(), allowed_events(), essential_events(), channel_of(jsonb),
  ingest(jsonb), place_order(jsonb), get_stock(), notify_restock(text, text, text),
  admin_order_action(text, text, text, text, text), admin_stock(text, text, int, text),
  admin_set_spend(date, numeric), admin_dashboard(date, date), admin_orders(text, int),
  admin_stock_view(), admin_restock_notified(bigint)
  from public, anon, authenticated;
grant execute on function ingest(jsonb), place_order(jsonb), get_stock(), notify_restock(text, text, text)
  to anon, authenticated;
grant execute on function is_site_admin(), admin_dashboard(date, date), admin_orders(text, int),
  admin_order_action(text, text, text, text, text), admin_stock(text, text, int, text),
  admin_set_spend(date, numeric), admin_stock_view(), admin_restock_notified(bigint)
  to authenticated;
-- Every admin_* function also checks is_site_admin() itself, so a signed-in app user gets "not allowed".

-- ───────────────────────── Last step: make yourself admin ─────────────────────────
-- Replace with the email you'll sign in with on glimp.in/admin, then run just this line:
-- insert into site_admins (email) values ('you@example.com') on conflict do nothing;
