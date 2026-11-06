# Email channel + the three alert policies of monitoring/alert_*.json
resource "google_monitoring_notification_channel" "email" {
  display_name = "Grupo 1 email"
  type         = "email"
  labels       = { email_address = var.alert_email }
}

resource "google_monitoring_alert_policy" "system_lag" {
  display_name          = "Dataflow system lag > 5 min"
  combiner              = "OR"
  notification_channels = [google_monitoring_notification_channel.email.id]
  conditions {
    display_name = "system_lag > 300 s during 5 min"
    condition_threshold {
      filter          = "resource.type = \"dataflow_job\" AND metric.type = \"dataflow.googleapis.com/job/system_lag\""
      comparison      = "COMPARISON_GT"
      threshold_value = 300
      duration        = "300s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }
  documentation {
    content   = "RPO < 5 min at risk. Check the Dataflow job; if it is down: streaming/launch_dataflow.sh (Pub/Sub keeps 7 days)."
    mime_type = "text/markdown"
  }
}

resource "google_monitoring_alert_policy" "pubsub_backlog" {
  display_name          = "Datos sin llegar a BigQuery: backlog Pub/Sub > 10 min"
  combiner              = "OR"
  notification_channels = [google_monitoring_notification_channel.email.id]
  conditions {
    display_name = "oldest_unacked_message_age > 600 s during 5 min"
    condition_threshold {
      filter          = "resource.type = \"pubsub_subscription\" AND resource.labels.subscription_id = \"${var.subscription}\" AND metric.type = \"pubsub.googleapis.com/subscription/oldest_unacked_message_age\""
      comparison      = "COMPARISON_GT"
      threshold_value = 600
      duration        = "300s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }
  documentation {
    content   = "Data freshness: Pub/Sub has events unprocessed for more than 10 min (Dataflow job down or stuck). Check the job; if it is down: streaming/launch_dataflow.sh (Pub/Sub keeps 7 days, nothing is lost)."
    mime_type = "text/markdown"
  }
}

resource "google_monitoring_alert_policy" "scheduled_query" {
  display_name          = "Scheduled query falló (refresco o chequeos de calidad)"
  combiner              = "OR"
  notification_channels = [google_monitoring_notification_channel.email.id]
  conditions {
    display_name = "Error en un run de BigQuery Data Transfer"
    condition_matched_log {
      filter = "resource.type=\"bigquery_dts_config\" AND severity>=ERROR"
    }
  }
  alert_strategy {
    auto_close = "86400s"
    notification_rate_limit {
      period = "3600s"
    }
  }
  documentation {
    content   = "refresco-diario-incremental or chequeos-calidad-diarios failed. If it is an ASSERT in sql/15_checks.sql, the message says which one: dead-letter growth, aggregates that do not match events_raw, duplicate streaming rows, a category jump or too many uncategorized purchases. See Transfers in BigQuery."
    mime_type = "text/markdown"
  }
}
