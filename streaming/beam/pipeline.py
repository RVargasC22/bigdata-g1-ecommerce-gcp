"""Streaming pipeline (Apache Beam): clean, enrich and aggregate REES46 events in real time.

Pub/Sub (own subscription, fan-out next to the template job) -> parse and validate -> enrich each event with
the product's common category (side input exported from dim_producto) -> count per (event minute, category)
in 1-minute arrival windows -> BigQuery gold table stream_categoria_minuto. Invalid messages go to
events_deadletter with the reason, in the same format as the template job, without stopping the stream.

Windows follow arrival time (Pub/Sub publish time, whose watermark Dataflow tracks exactly) and the key carries
the event's own minute. Panes are discarding, so every event is counted in exactly one row: readers SUM the rows
of a (minute, category). Live events land in the window of their own minute (one row each); a replay of 2019
events at 10x also adds up to the batch numbers (sql/19_stream_aggregates.sql, conciliar_stream, checks it).
Windowing on the 2019 event time instead would make every replayed event years late for the watermark.
"""
import argparse
import base64
import csv
import json
import re
from datetime import datetime, timezone

import apache_beam as beam
from apache_beam.io.gcp.bigquery import BigQueryDisposition, WriteToBigQuery
from apache_beam.metrics import Metrics
from apache_beam.options.pipeline_options import PipelineOptions, StandardOptions
from apache_beam.transforms import window
from apache_beam.transforms.trigger import AccumulationMode, AfterProcessingTime, AfterWatermark

TS_RE = re.compile(r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}( UTC)?$")
INT_RE = re.compile(r"^\d+$")
EVENT_TYPES = ("view", "cart", "remove_from_cart", "purchase")
INVALID = "invalid"
UNKNOWN_CATEGORY = "sin_categoria"
# Elements that reach a window after it closed are still counted for 10 minutes, in extra (late) rows every 30 s
ALLOWED_LATENESS_S = 600


def parse_event(payload):
    """Returns the cleaned event as a dict, or raises ValueError with the reason (same rules as the JS UDF)."""
    e = json.loads(payload)
    ts = e.get("event_time") or ""
    if not TS_RE.match(ts):
        raise ValueError(f"invalid event_time: {ts}")
    if e.get("event_type") not in EVENT_TYPES:
        raise ValueError(f"invalid event_type: {e.get('event_type')}")
    product_id = str(e.get("product_id") or "")
    if not INT_RE.match(product_id):
        raise ValueError(f"invalid product_id: {product_id}")
    price = e.get("price")
    if price in (None, ""):
        price = 0.0
    else:
        price = float(price)
        if price < 0:
            raise ValueError(f"invalid price: {price}")
    return {
        "event_time": datetime.strptime(ts[:19], "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc),
        "event_type": e["event_type"],
        "product_id": int(product_id),
        "price": price,
    }


class ParseAndValidate(beam.DoFn):
    """Main output: cleaned events. Tagged output 'invalid': dead-letter rows."""

    def __init__(self):
        super().__init__()
        self.invalid = Metrics.counter("stream", "mensajes_invalidos")

    def process(self, payload):
        raw = payload if isinstance(payload, bytes) else payload.encode("utf-8")
        text = raw.decode("utf-8", errors="replace")
        try:
            ev = parse_event(text)
        except (ValueError, TypeError, KeyError) as err:  # json.JSONDecodeError is a ValueError
            self.invalid.inc()
            yield beam.pvalue.TaggedOutput(INVALID, {
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "payloadString": text,
                "payloadBytes": base64.b64encode(raw).decode("ascii"),  # required column (template format)
                "errorMessage": f"beam: {err}",
            })
            return
        yield ev


def enrich(ev, categories):
    """Adds the common category of the product; products unknown to dim_producto stay as sin_categoria."""
    return {**ev, "categoria_comun": categories.get(ev["product_id"], UNKNOWN_CATEGORY)}


def parse_lookup_line(line):
    product_id, categoria = next(csv.reader([line]))
    return int(product_id), categoria


class CountByType(beam.CombineFn):
    """Per window, event minute and category: events by type and purchase revenue."""

    def create_accumulator(self):
        return {"eventos": 0, "vistas": 0, "carritos": 0, "remociones": 0, "compras": 0, "ingresos": 0.0}

    def add_input(self, acc, ev):
        acc["eventos"] += 1
        key = {"view": "vistas", "cart": "carritos", "remove_from_cart": "remociones", "purchase": "compras"}
        acc[key[ev["event_type"]]] += 1
        if ev["event_type"] == "purchase":
            acc["ingresos"] += ev["price"]
        return acc

    def merge_accumulators(self, accs):
        out = self.create_accumulator()
        for a in accs:
            for k in out:
                out[k] += a[k]
        return out

    def extract_output(self, acc):
        return acc


class ToRow(beam.DoFn):
    def process(self, kv, win=beam.DoFn.WindowParam, pane=beam.DoFn.PaneInfoParam):
        (minuto, categoria), c = kv
        if c["eventos"] == 0:  # the window's closing late pane is empty when nothing arrived late
            return
        yield {
            "minuto": minuto,
            "ventana": win.start.to_utc_datetime().replace(tzinfo=timezone.utc).isoformat(),
            "categoria_comun": categoria,
            **c,
            "ingresos": round(c["ingresos"], 2),
            "disparo": {0: "anticipado", 1: "a_tiempo", 2: "tardio"}.get(pane.timing, "desconocido"),
            "procesado_en": datetime.now(timezone.utc).isoformat(),
        }


def build(p, source, lookup_path, window_seconds=60):
    """Shared by the Dataflow job and the unit test. Returns (aggregated rows, dead-letter rows)."""
    categories = (p
                  | "LeerCategorias" >> beam.io.ReadFromText(lookup_path, skip_header_lines=1)
                  | "ParsearCategorias" >> beam.Map(parse_lookup_line))
    parsed = source | "Validar" >> beam.ParDo(ParseAndValidate()).with_outputs(INVALID, main="ok")
    rows = (parsed.ok
            | "Enriquecer" >> beam.Map(enrich, categories=beam.pvalue.AsDict(categories))
            | "VentanaMinuto" >> beam.WindowInto(
                window.FixedWindows(window_seconds), trigger=AfterWatermark(late=AfterProcessingTime(30)),
                accumulation_mode=AccumulationMode.DISCARDING, allowed_lateness=ALLOWED_LATENESS_S)
            | "PorMinutoYCategoria" >> beam.Map(lambda ev: (
                (ev["event_time"].replace(second=0).isoformat(), ev["categoria_comun"]), ev))
            | "Contar" >> beam.CombinePerKey(CountByType())
            | "AFila" >> beam.ParDo(ToRow()))
    return rows, parsed[INVALID]


def run(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--subscription", required=True, help="projects/<p>/subscriptions/<s>")
    ap.add_argument("--lookup", required=True, help="gs://.../dim_producto_categoria.csv")
    ap.add_argument("--output_table", required=True, help="<project>:<dataset>.stream_categoria_minuto")
    ap.add_argument("--deadletter_table", required=True, help="<project>:<dataset>.events_deadletter")
    known, beam_args = ap.parse_known_args(argv)
    opts = PipelineOptions(beam_args)
    opts.view_as(StandardOptions).streaming = True

    p = beam.Pipeline(options=opts)
    source = p | "LeerPubSub" >> beam.io.ReadFromPubSub(subscription=known.subscription)
    rows, invalid = build(p, source, known.lookup)
    rows | "EscribirAgregados" >> WriteToBigQuery(
        known.output_table, method=WriteToBigQuery.Method.STREAMING_INSERTS,
        create_disposition=BigQueryDisposition.CREATE_NEVER,
        write_disposition=BigQueryDisposition.WRITE_APPEND)
    invalid | "EscribirErrores" >> WriteToBigQuery(
        known.deadletter_table, method=WriteToBigQuery.Method.STREAMING_INSERTS,
        create_disposition=BigQueryDisposition.CREATE_NEVER,
        write_disposition=BigQueryDisposition.WRITE_APPEND)
    result = p.run()  # a streaming job never finishes: submit and return
    print("Submitted job:", getattr(result, "job_id", lambda: "local")())


if __name__ == "__main__":
    run()
