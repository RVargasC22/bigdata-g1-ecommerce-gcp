# Adopt the resources created by infra/*.sh and monitoring/setup_alerts.sh (Terraform >= 1.7).
# After the first successful apply these blocks can stay (no-op) or be deleted.
locals {
  p       = "projects/${var.project_id}"
  sa_mail = { for k in keys(local.service_accounts) : k => "serviceAccount:${k}@${var.project_id}.iam.gserviceaccount.com" }
  tax     = "${local.p}/locations/us/taxonomies/2783235129463687013"
  tag_ids = {
    identificador_usuario = "${local.tax}/policyTags/8966460537517634699"
    identificador_cliente = "${local.tax}/policyTags/1413268479241578379"
  }
}

import {
  for_each = toset(local.services)
  to       = google_project_service.api[each.value]
  id       = "${var.project_id}/${each.value}"
}
import {
  to = google_storage_bucket.raw
  id = var.bucket
}
import {
  for_each = toset([var.dataset, var.dr_dataset])
  to       = google_bigquery_dataset.ds[each.value]
  id       = "${local.p}/datasets/${each.value}"
}
import {
  to = google_pubsub_topic.events
  id = "${local.p}/topics/${var.topic}"
}
import {
  to = google_pubsub_subscription.dataflow
  id = "${local.p}/subscriptions/${var.subscription}"
}
import {
  to = google_pubsub_subscription.beam
  id = "${local.p}/subscriptions/${var.subscription_beam}"
}
import {
  to = google_secret_manager_secret.kaggle
  id = "${local.p}/secrets/kaggle-token"
}
import {
  for_each = local.service_accounts
  to       = google_service_account.sa[each.key]
  id       = "${local.p}/serviceAccounts/${each.key}@${var.project_id}.iam.gserviceaccount.com"
}
import {
  for_each = local.project_roles
  to       = google_project_iam_member.sa[each.key]
  id       = "${var.project_id} ${each.value.role} ${local.sa_mail[each.value.sa]}"
}
import {
  for_each = toset(["sa-ingesta", "sa-dataflow"])
  to       = google_storage_bucket_iam_member.sa[each.value]
  id       = "b/${var.bucket} roles/storage.objectUser ${local.sa_mail[each.value]}"
}
import {
  to = google_pubsub_topic_iam_member.ingesta_publisher
  id = "${local.p}/topics/${var.topic} roles/pubsub.publisher ${local.sa_mail["sa-ingesta"]}"
}
import {
  for_each = toset(["roles/pubsub.subscriber", "roles/pubsub.viewer"])
  to       = google_pubsub_subscription_iam_member.dataflow[each.value]
  id       = "${local.p}/subscriptions/${var.subscription} ${each.value} ${local.sa_mail["sa-dataflow"]}"
}
import {
  for_each = toset(["roles/pubsub.subscriber", "roles/pubsub.viewer"])
  to       = google_pubsub_subscription_iam_member.beam[each.value]
  id       = "${local.p}/subscriptions/${var.subscription_beam} ${each.value} ${local.sa_mail["sa-dataflow"]}"
}
import {
  to = google_secret_manager_secret_iam_member.ingesta_accessor
  id = "${local.p}/secrets/kaggle-token roles/secretmanager.secretAccessor ${local.sa_mail["sa-ingesta"]}"
}
import {
  for_each = toset(["sa-dataflow", "sa-transform"])
  to       = google_bigquery_dataset_iam_member.editor[each.value]
  id       = "${local.p}/datasets/${var.dataset} roles/bigquery.dataEditor ${local.sa_mail[each.value]}"
}
import {
  to = google_data_catalog_taxonomy.pii
  id = local.tax
}
import {
  for_each = local.tag_ids
  to       = google_data_catalog_policy_tag.pii[each.key]
  id       = each.value
}
import { # team readers + sa-transform (granted by infra/04_fine_grained_access.py)
  for_each = { for pair in setproduct(keys(local.tag_ids), concat(var.full_readers, [local.sa_mail["sa-transform"]])) : "${pair[0]}|${pair[1]}" => pair }
  to       = google_data_catalog_policy_tag_iam_member.reader[each.key]
  id       = "${local.tag_ids[each.value[0]]} roles/datacatalog.categoryFineGrainedReader ${each.value[1]}"
}
import {
  to = google_monitoring_notification_channel.email
  id = "${local.p}/notificationChannels/14328033163746146836"
}
import {
  to = google_monitoring_alert_policy.system_lag
  id = "${local.p}/alertPolicies/11915353254225924117"
}
import {
  to = google_monitoring_alert_policy.pubsub_backlog
  id = "${local.p}/alertPolicies/16897591163614697740"
}
import {
  to = google_monitoring_alert_policy.scheduled_query
  id = "${local.p}/alertPolicies/1077187334659922822"
}
