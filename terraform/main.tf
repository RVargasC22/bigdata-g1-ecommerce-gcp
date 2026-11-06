# Infrastructure as code for the platform's persistent resources. The resources were first created by the
# infra/*.sh scripts; imports.tf adopts them into the state, so `terraform plan` must show no destroys.
# Not managed here (by design):
#   - BigQuery tables: created by the SQL layer (sql/*.sql); their schema evolves with the transformations.
#   - Dataflow job: launched per streaming window (streaming/launch_dataflow.sh) and drained afterwards.
#   - Ingestion VM: ephemeral (infra/02_vm.sh), deleted after each load.
#   - Secret value (Kaggle token): never written to the Terraform state; versions added with gcloud.
#   - Budget (needs the billing administrator account) and the Dataplex glossary (infra/05_gobierno.sh).
#   - Removing Editor from the default Compute SA: Terraform members are additive (infra/00_iam.sh does it).

terraform {
  required_version = ">= 1.7"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 8.0"
    }
  }
  # Shared state for the team (bucket must exist first):
  # backend "gcs" { bucket = "bigdata-g1-ecommerce-1105-raw"  prefix = "terraform/state" }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  services = [
    "bigquery.googleapis.com", "bigquerydatatransfer.googleapis.com", "bigquerystorage.googleapis.com",
    "compute.googleapis.com", "datacatalog.googleapis.com", "dataflow.googleapis.com",
    "datalineage.googleapis.com", "dataplex.googleapis.com", "iam.googleapis.com", "logging.googleapis.com",
    "monitoring.googleapis.com", "pubsub.googleapis.com", "secretmanager.googleapis.com",
    "storage.googleapis.com",
  ]
}

resource "google_project_service" "api" {
  for_each           = toset(local.services)
  service            = each.value
  disable_on_destroy = false
}

# Data lake: multi-region US, versioned, lifecycle Standard -> Nearline (30 d) -> Coldline (90 d)
resource "google_storage_bucket" "raw" {
  name                        = var.bucket
  location                    = "US"
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  labels                      = { componente = "storage" }

  versioning {
    enabled = true
  }
  lifecycle_rule {
    condition {
      age                   = 30
      matches_storage_class = ["STANDARD"]
      matches_prefix        = ["raw/"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  lifecycle_rule {
    condition {
      age                   = 90
      matches_storage_class = ["NEARLINE"]
      matches_prefix        = ["raw/"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  lifecycle_rule {
    condition {
      days_since_noncurrent_time = 30
      with_state                 = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }
  lifecycle_rule {
    condition {
      age            = 7
      matches_prefix = ["dataflow/temp/"]
    }
    action {
      type = "Delete"
    }
  }
  lifecycle {
    prevent_destroy = true
  }
}

# Warehouse (and disaster-recovery copy): multi-region US, 7-day time travel
resource "google_bigquery_dataset" "ds" {
  for_each              = toset([var.dataset, var.dr_dataset])
  dataset_id            = each.value
  location              = "US"
  max_time_travel_hours = "168"
  labels                = { componente = "bigquery" }
  lifecycle {
    prevent_destroy = true
  }
}

# Ingest queue: 7-day retention so a stopped Dataflow job can replay the backlog
resource "google_pubsub_topic" "events" {
  name                       = var.topic
  message_retention_duration = "604800s"
  labels                     = { componente = "pubsub" }
}

resource "google_pubsub_subscription" "dataflow" {
  name                       = var.subscription
  topic                      = google_pubsub_topic.events.id
  ack_deadline_seconds       = 60
  message_retention_duration = "604800s"
  labels                     = { componente = "pubsub" }
  expiration_policy {
    ttl = "2678400s"
  }
}

# Kaggle token: only the container; the value is added with `gcloud secrets versions add` (never in state)
resource "google_secret_manager_secret" "kaggle" {
  secret_id = "kaggle-token"
  replication {
    auto {}
  }
}
