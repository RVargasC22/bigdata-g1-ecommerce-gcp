"""Unit test of the streaming transforms on the local DirectRunner: validation, enrichment and windows.

Run: python -m pytest streaming/beam/test_pipeline.py
"""
import json

import apache_beam as beam
from apache_beam.testing.test_pipeline import TestPipeline
from apache_beam.testing.util import assert_that, equal_to
from apache_beam.transforms.window import TimestampedValue

from pipeline import build


def msg(ts, event_type, product_id, price="10.5"):
    return json.dumps({"event_time": ts, "event_type": event_type, "product_id": product_id,
                       "price": price, "user_id": "1", "user_session": "s"}).encode()


def test_windows_enrichment_and_deadletter(tmp_path):
    lookup = tmp_path / "lookup.csv"
    lookup.write_text("product_id,categoria_comun\n1,electronica\n2,muebles\n")
    messages = [
        msg("2019-11-17 10:00:05 UTC", "view", "1"),
        msg("2019-11-17 10:00:40 UTC", "cart", "1"),
        msg("2019-11-17 10:00:59 UTC", "purchase", "1"),
        msg("2019-11-17 10:01:00 UTC", "purchase", "2", "100"),   # next minute
        msg("2019-11-17 10:01:30 UTC", "view", "999"),             # product not in dim_producto
        msg("2019-11-17 10:01:31 UTC", "hack", "1"),               # invalid type
        b"not json",
        msg("2019-11-17 10:01:32 UTC", "purchase", "1", "-5"),     # negative price
    ]
    with TestPipeline() as p:
        # all messages "arrive" in the same minute (one window), so each (minute, category) yields one row
        source = p | beam.Create(messages) | beam.Map(lambda m: TimestampedValue(m, 1_762_400_000))
        rows, invalid = build(p, source, str(lookup))
        summary = rows | beam.Map(lambda r: (r["minuto"], r["categoria_comun"], r["eventos"], r["vistas"],
                                             r["carritos"], r["compras"], r["ingresos"]))
        assert_that(summary, equal_to([
            ("2019-11-17T10:00:00+00:00", "electronica", 3, 1, 1, 1, 10.5),
            ("2019-11-17T10:01:00+00:00", "muebles", 1, 0, 0, 1, 100.0),
            ("2019-11-17T10:01:00+00:00", "sin_categoria", 1, 1, 0, 0, 0.0),
        ]), label="agregados")
        reasons = invalid | beam.Map(lambda r: r["errorMessage"].split(":")[1].strip())
        assert_that(reasons, equal_to(["invalid event_type", "Expecting value", "invalid price"]),
                    label="errores")
