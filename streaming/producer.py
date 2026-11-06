"""Replays a REES46 CSV into Pub/Sub in event_time order, compressed in time by --speedup."""
import argparse
import csv
import json
import time
from datetime import datetime, timezone

from google.cloud import pubsub_v1
from google.cloud.pubsub_v1.types import BatchSettings, LimitExceededBehavior, PublishFlowControl, PublisherOptions


def parse_ts(s):
    return datetime.strptime(s[:19], "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv_path")
    ap.add_argument("--project", required=True)
    ap.add_argument("--topic", required=True)
    ap.add_argument("--speedup", type=float, default=10.0, help="0 = publish as fast as possible")
    ap.add_argument("--max-events", type=int, default=0)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    publisher = None if a.dry_run else pubsub_v1.PublisherClient(
        batch_settings=BatchSettings(max_messages=1000, max_bytes=1_000_000, max_latency=0.05),
        publisher_options=PublisherOptions(flow_control=PublishFlowControl(
            message_limit=20_000, limit_exceeded_behavior=LimitExceededBehavior.BLOCK)),
    )
    topic = f"projects/{a.project}/topics/{a.topic}"
    failed = 0

    def on_done(fut):
        nonlocal failed
        if fut.exception():
            failed += 1

    t0_event = t0_wall = None
    sent = 0
    last_report = time.monotonic()
    with open(a.csv_path, newline="") as f:
        for row in csv.DictReader(f):
            ev = parse_ts(row["event_time"])
            if t0_event is None:
                t0_event, t0_wall = ev, time.monotonic()
            if a.speedup > 0:
                wait = t0_wall + (ev - t0_event).total_seconds() / a.speedup - time.monotonic()
                if wait > 0:
                    time.sleep(wait)
            data = json.dumps(row).encode()
            if a.dry_run:
                if sent < 3:
                    print(data.decode())
            else:
                publisher.publish(topic, data, event_type=row["event_type"]).add_done_callback(on_done)
            sent += 1
            if time.monotonic() - last_report >= 30:
                el = time.monotonic() - t0_wall
                print(f"{sent} events, {sent / el:.0f} ev/s, event_time={row['event_time']}, failed={failed}", flush=True)
                last_report = time.monotonic()
            if a.max_events and sent >= a.max_events:
                break

    if publisher:
        publisher.stop()
    el = time.monotonic() - (t0_wall or time.monotonic())
    print(f"DONE {sent} events in {el:.0f}s ({sent / max(el, 1e-9):.0f} ev/s), failed={failed}")


if __name__ == "__main__":
    main()
