"""Runs on the replay VM (streaming/beam/test_replay.sh): sorts the exported slice by event_time, publishes
3 invalid messages for the dead-letter test and replays the slice at 10x with streaming/producer.py."""
import csv
import glob
import subprocess
import sys
from datetime import datetime, timezone

from google.cloud import pubsub_v1

project, topic = sys.argv[1], sys.argv[2]

rows, header = [], None
for f in sorted(glob.glob("beam_test-*.csv")):
    with open(f, newline="") as fh:
        r = csv.reader(fh)
        header = next(r)
        rows += list(r)
rows.sort(key=lambda x: x[0])
with open("slice.csv", "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(header)
    w.writerows(rows)
print(f"slice: {len(rows)} events {rows[0][0]} - {rows[-1][0]}", flush=True)

bad = [
    b'{"event_time": "2019-11-17 10:05:00 UTC", "event_type": "hack", "product_id": "1"}',
    b"no es json",
    b'{"event_time": "2019-11-17 10:05:00 UTC", "event_type": "purchase", "product_id": "1", "price": "-5"}',
]
pub = pubsub_v1.PublisherClient()
for m in bad:
    pub.publish(f"projects/{project}/topics/{topic}", m, prueba="beam_deadletter").result()
print("published 3 invalid messages", flush=True)

print("START", datetime.now(timezone.utc).isoformat(), flush=True)
subprocess.run([sys.executable, "producer.py", "slice.csv", "--project", project, "--topic", topic,
                "--speedup", "10"], check=True)
print("END", datetime.now(timezone.utc).isoformat(), flush=True)
