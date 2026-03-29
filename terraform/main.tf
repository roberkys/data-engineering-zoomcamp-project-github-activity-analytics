terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  credentials = file(var.credentials_file)
  project     = var.project
  region      = var.region
}

# --- Data Lake (GCS) ---

resource "google_storage_bucket" "data_lake" {
  name          = var.gcs_bucket_name
  location      = var.location
  force_destroy = true

  lifecycle_rule {
    condition { age = 90 }
    action { type = "Delete" }
  }

  uniform_bucket_level_access = true
}

# --- Raw ingestion dataset ---

resource "google_bigquery_dataset" "raw" {
  dataset_id  = var.bq_dataset_raw
  location    = var.location
  description = "Raw GitHub Archive events loaded by Kestra"
}

resource "google_bigquery_table" "events" {
  dataset_id          = google_bigquery_dataset.raw.dataset_id
  table_id            = "events"
  deletion_protection = false
  description         = "GitHub Archive events – partitioned by day, clustered by event type and repo"

  # Partition by event day → significant query cost reduction
  time_partitioning {
    type  = "DAY"
    field = "created_at"
  }

  # Cluster by the two most common filter dimensions
  clustering = ["type", "repo_name"]

  schema = jsonencode([
    { name = "id",          type = "STRING",    mode = "NULLABLE", description = "Unique event ID" },
    { name = "type",        type = "STRING",    mode = "NULLABLE", description = "GitHub event type (e.g. PushEvent)" },
    { name = "created_at",  type = "TIMESTAMP", mode = "NULLABLE", description = "UTC timestamp of the event" },
    { name = "public",      type = "BOOLEAN",   mode = "NULLABLE", description = "Whether the event is public" },
    { name = "actor_login", type = "STRING",    mode = "NULLABLE", description = "GitHub username who triggered the event" },
    { name = "actor_id",    type = "INTEGER",   mode = "NULLABLE", description = "Numeric actor user ID" },
    { name = "repo_name",   type = "STRING",    mode = "NULLABLE", description = "Repository in owner/repo format" },
    { name = "repo_id",     type = "INTEGER",   mode = "NULLABLE", description = "Numeric repository ID" }
  ])
}

# --- Data Warehouse dataset (populated by dbt) ---

resource "google_bigquery_dataset" "dwh" {
  dataset_id  = var.bq_dataset_dwh
  location    = var.location
  description = "Transformed GitHub analytics models produced by dbt"
}
