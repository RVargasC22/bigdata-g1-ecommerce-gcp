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
    content   = "RPO < 5 min en riesgo. Revisar el job en Dataflow; si cayó: streaming/launch_dataflow.sh (Pub/Sub retiene 7 días)."
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
    content   = "Frescura de datos: hay eventos en Pub/Sub sin procesar hace más de 10 min (job de Dataflow caído o atascado). Revisar el job; si cayó: streaming/launch_dataflow.sh (Pub/Sub retiene 7 días, no se pierde nada)."
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
    content   = "Falló refresco-diario-incremental o chequeos-calidad-diarios. Si es un ASSERT de sql/18_chequeos.sql, el mensaje dice cuál: crecimiento del dead-letter, agregados que no cuadran con events_raw o duplicados del streaming sin limpiar. Ver Transferencias en BigQuery."
    mime_type = "text/markdown"
  }
}
