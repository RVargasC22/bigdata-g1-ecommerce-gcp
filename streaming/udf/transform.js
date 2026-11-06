// Dataflow UDF (ES5). Validates and normalizes one REES46 event.
// Throwing routes the message to the dead-letter table instead of events_raw.
var VALID_TYPES = {view: true, cart: true, remove_from_cart: true, purchase: true};
var TS_RE = /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/;
var INT_RE = /^\d+$/;

function blank(v) {
  return v === undefined || v === null || v === '';
}

function intOrNull(v, name) {
  if (blank(v)) return null;
  if (!INT_RE.test(String(v))) throw 'invalid ' + name + ': ' + v;
  return String(v);
}

function transform(line) {
  var e = JSON.parse(line);
  if (blank(e.event_time) || !TS_RE.test(e.event_time)) throw 'invalid event_time: ' + e.event_time;
  if (!VALID_TYPES[e.event_type]) throw 'invalid event_type: ' + e.event_type;
  var price = null;
  if (!blank(e.price)) {
    price = Number(e.price);
    if (isNaN(price) || price < 0) throw 'invalid price: ' + e.price;
  }
  return JSON.stringify({
    event_time: e.event_time.substring(0, 19),
    event_type: e.event_type,
    product_id: intOrNull(e.product_id, 'product_id'),
    category_id: intOrNull(e.category_id, 'category_id'),
    category_code: blank(e.category_code) ? null : e.category_code,
    brand: blank(e.brand) ? null : e.brand,
    price: price,
    user_id: intOrNull(e.user_id, 'user_id'),
    user_session: blank(e.user_session) ? null : e.user_session,
    source: 'stream',
    ingest_time: new Date().toISOString()
  });
}
