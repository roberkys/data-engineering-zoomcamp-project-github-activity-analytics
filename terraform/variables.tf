variable "credentials_file" {
  description = "Path to the GCP service account JSON key file"
  type        = string
  default     = "../keys/sa_key.json"
}

variable "project" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "location" {
  description = "GCP multi-region location for BigQuery and GCS"
  type        = string
  default     = "US"
}

variable "gcs_bucket_name" {
  description = "GCS bucket name for the data lake (must be globally unique)"
  type        = string
}

variable "bq_dataset_raw" {
  description = "BigQuery dataset for raw ingested data"
  type        = string
  default     = "github_archive_raw"
}

variable "bq_dataset_dwh" {
  description = "BigQuery dataset for dbt-transformed data warehouse models"
  type        = string
  default     = "github_analytics_dwh"
}
