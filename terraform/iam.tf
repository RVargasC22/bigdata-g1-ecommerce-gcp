# One service account per component, least privilege (same as infra/02_iam.sh)
locals {
  service_accounts = {
    "sa-ingesta"   = "Ingesta: VM de descarga y productor de replay"
    "sa-dataflow"  = "Dataflow: Pub/Sub -> BigQuery"
    "sa-transform" = "Consultas programadas de BigQuery"
  }
  sa = { for k, v in google_service_account.sa : k => "serviceAccount:${v.email}" }

  project_roles = {
    "ingesta-monitoring-viewer" = { sa = "sa-ingesta", role = "roles/monitoring.viewer" }
    "ingesta-log-writer"        = { sa = "sa-ingesta", role = "roles/logging.logWriter" }
    "ingesta-metric-writer"     = { sa = "sa-ingesta", role = "roles/monitoring.metricWriter" }
    "dataflow-worker"           = { sa = "sa-dataflow", role = "roles/dataflow.worker" }
    "transform-job-user"        = { sa = "sa-transform", role = "roles/bigquery.jobUser" }
  }
  # Readers of the policy-tagged columns: team + sa-transform (stream dedup in sql/14 compares whole rows)
  tag_readers = concat(var.full_readers, [local.sa["sa-transform"]])
  tag_grants = merge([for tag in keys(google_data_catalog_policy_tag.pii) : {
    for m in local.tag_readers : "${tag}|${m}" => { tag = tag, member = m }
  }]...)
}

resource "google_service_account" "sa" {
  for_each     = local.service_accounts
  account_id   = each.key
  display_name = each.value
}

resource "google_project_iam_member" "sa" {
  for_each = local.project_roles
  project  = var.project_id
  role     = each.value.role
  member   = local.sa[each.value.sa]
}

resource "google_storage_bucket_iam_member" "sa" {
  for_each = toset(["sa-ingesta", "sa-dataflow"])
  bucket   = google_storage_bucket.raw.name
  role     = "roles/storage.objectUser"
  member   = local.sa[each.value]
}

resource "google_pubsub_topic_iam_member" "ingesta_publisher" {
  topic  = google_pubsub_topic.events.id
  role   = "roles/pubsub.publisher"
  member = local.sa["sa-ingesta"]
}

resource "google_pubsub_subscription_iam_member" "dataflow" {
  for_each     = toset(["roles/pubsub.subscriber", "roles/pubsub.viewer"])
  subscription = google_pubsub_subscription.dataflow.id
  role         = each.value
  member       = local.sa["sa-dataflow"]
}

resource "google_secret_manager_secret_iam_member" "ingesta_accessor" {
  secret_id = google_secret_manager_secret.kaggle.id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.sa["sa-ingesta"]
}

resource "google_bigquery_dataset_iam_member" "editor" {
  for_each   = toset(["sa-dataflow", "sa-transform"])
  dataset_id = google_bigquery_dataset.ds[var.dataset].dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = local.sa[each.value]
}

# Column-level security: taxonomy + policy tags (attached to columns by infra/04_fine_grained_access.py)
resource "google_data_catalog_taxonomy" "pii" {
  region                 = "us"
  display_name           = "datos-personales"
  description            = "Identificadores de personas (glosario: Dato personal)."
  activated_policy_types = ["FINE_GRAINED_ACCESS_CONTROL"]
}

resource "google_data_catalog_policy_tag" "pii" {
  for_each = {
    identificador_usuario = "user_id de REES46"
    identificador_cliente = "customer_unique_id de Olist"
  }
  taxonomy     = google_data_catalog_taxonomy.pii.id
  display_name = each.key
  description  = each.value
}

resource "google_data_catalog_policy_tag_iam_member" "reader" {
  for_each   = local.tag_grants
  policy_tag = google_data_catalog_policy_tag.pii[each.value.tag].name
  role       = "roles/datacatalog.categoryFineGrainedReader"
  member     = each.value.member
}
