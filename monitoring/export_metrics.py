"""Exports peak-test metrics (workers, vCPUs, system lag, Pub/Sub backlog, throughput) to CSV, one row per minute."""
import argparse
import csv
import time

from google.cloud import monitoring_v3

METRICS = {
    "vcpus": ('dataflow.googleapis.com/job/current_num_vcpus', "ALIGN_MAX"),
    "system_lag_s": ('dataflow.googleapis.com/job/system_lag', "ALIGN_MAX"),
    "watermark_age_s": ('dataflow.googleapis.com/job/data_watermark_age', "ALIGN_MAX"),
    "backlog_msgs": ('pubsub.googleapis.com/subscription/num_undelivered_messages', "ALIGN_MAX"),
    "publish_msgs_per_s": ('pubsub.googleapis.com/topic/send_message_operation_count', "ALIGN_RATE"),
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", required=True)
    ap.add_argument("--hours", type=float, default=4)
    ap.add_argument("--out", default="metricas_pico.csv")
    a = ap.parse_args()

    client = monitoring_v3.MetricServiceClient()
    now = int(time.time())
    interval = monitoring_v3.TimeInterval(end_time={"seconds": now}, start_time={"seconds": now - int(a.hours * 3600)})
    rows = {}
    for col, (metric, aligner) in METRICS.items():
        series = client.list_time_series(request={
            "name": f"projects/{a.project}",
            "filter": f'metric.type = "{metric}"',
            "interval": interval,
            "view": monitoring_v3.ListTimeSeriesRequest.TimeSeriesView.FULL,
            "aggregation": {
                "alignment_period": {"seconds": 60},
                "per_series_aligner": getattr(monitoring_v3.Aggregation.Aligner, aligner),
                "cross_series_reducer": monitoring_v3.Aggregation.Reducer.REDUCE_SUM,
            },
        })
        for s in series:
            for p in s.points:
                ts = p.interval.end_time.isoformat()
                v = p.value.double_value or p.value.int64_value
                rows.setdefault(ts, {})[col] = v

    with open(a.out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["minute", *METRICS])
        w.writeheader()
        for ts in sorted(rows):
            w.writerow({"minute": ts, **rows[ts]})
    print(f"{len(rows)} minutes -> {a.out}")


if __name__ == "__main__":
    main()
