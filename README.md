# GitHub Activity Analytics Dashboard

An end-to-end data pipeline that ingests **GitHub Archive** event data into BigQuery,
transforms it with dbt, and visualises it in a Looker Studio dashboard.

Built as the final project for the [Data Engineering Zoomcamp](https://github.com/DataTalksClub/data-engineering-zoomcamp).

---

## Problem Statement

GitHub generates millions of public events every day (pushes, pull requests, issues, forks, etc.).
This project answers two questions that any developer or engineering leader finds useful:

1. **How has GitHub activity trended over time?** (temporal distribution)
2. **What types of events dominate developer activity?** (categorical distribution)

The pipeline processes the [GitHub Archive](https://www.gharchive.org/) – a public record of
every GitHub public event since 2011 – and surfaces the answers in an interactive dashboard.

---

## Architecture

```
GH Archive (hourly JSON.gz)
        │
        ▼
[Kestra] 02_ingest flow (daily schedule)
  • Downloads 24 hourly files
  • Flattens nested JSON → 8-field rows
  • Loads directly into BigQuery via load_table_from_json
        │
        ▼
BigQuery: github_archive_raw.events
  (partitioned by DAY/created_at, clustered by type + repo_name)
        │
        ▼
[dbt] 03_dbt_transform flow (triggered after ingest)
  • stg_github_events          (view, deduplicated)
  • fct_daily_activity         (partitioned table)
  • fct_event_type_distribution(table)
  • fct_top_repos              (view)
        │
        ▼
BigQuery: github_analytics_dwh.*
        │
        ▼
Looker Studio Dashboard (2 tiles)
```

## Technologies

| Layer | Tool |
|-------|------|
| Cloud | GCP (BigQuery) |
| IaC | Terraform |
| Orchestration | Kestra |
| Data Warehouse | BigQuery (partitioned + clustered) |
| Transformations | dbt (dbt-bigquery) |
| Dashboard | Looker Studio |

---

## Dashboard

The Looker Studio dashboard contains two tiles:

- **Tile 1 – GitHub activity over time** (line chart): daily event count per event type,
  showing temporal trends across the selected period.
- **Tile 2 – Event type distribution** (bar chart): share of each event type
  (PushEvent, PullRequestEvent, WatchEvent, etc.) across the full dataset.

> **[View the live dashboard](https://lookerstudio.google.com/reporting/bc40761b-76a5-4102-a9b2-653f9458b4c0)** (public, no login required)

---

## Project Structure

```
├── terraform/
│   ├── main.tf           # GCS bucket, BigQuery datasets and raw events table
│   └── variables.tf
│
├── kestra/
│   ├── docker-compose.yml
│   └── flows/
│       ├── 01_setup_kv.yaml      # One-time KV store setup
│       ├── 02_ingest.yaml        # Daily ingest: GH Archive → GCS → BigQuery
│       ├── 03_dbt_transform.yaml # dbt run (auto-triggered after ingest)
│       └── 04_backfill.yaml      # Historical backfill for a date range
│
└── dbt/github_analytics/
    ├── dbt_project.yml
    ├── packages.yml
    ├── profiles.yml
    └── models/
        ├── staging/
        │   ├── stg_github_events.sql
        │   └── schema.yml
        └── marts/
            ├── fct_daily_activity.sql
            ├── fct_event_type_distribution.sql
            ├── fct_top_repos.sql
            └── schema.yml
```

---

## Reproducibility

### Prerequisites

- GCP project with billing enabled
- Terraform ≥ 1.5
- Docker + Docker Compose

### 1 – Clone the repo

```bash
git clone https://github.com/roberkys/data-engineering-zoomcamp-project-github-activity-analytics.git
cd data-engineering-zoomcamp-project-github-activity-analytics
```

### 2 – Configure environment variables

```bash
cp .env.example .env
```

Edit `.env` and fill in every value:

| Variable | Description |
|---|---|
| `GCP_PROJECT_ID` | Your GCP project ID |
| `GCP_LOCATION` | BigQuery/GCS location (e.g. `US`) |
| `GCP_BUCKET_NAME` | Unique GCS bucket name (will be created by Terraform) |
| `GCP_CREDS` | Service account JSON **base64-encoded** (see below) |
| `KESTRA_USERNAME` | Kestra UI login (default: `admin@kestra.io`) |
| `KESTRA_PASSWORD` | Kestra UI password (default: `Admin1234!`) |

**How to generate `GCP_CREDS`:**

1. Create a GCP service account with roles: BigQuery Admin, Storage Admin
2. Download the JSON key → save as `keys/sa_key.json`
3. Base64-encode it:
   ```bash
   # Mac / Linux
   base64 -i keys/sa_key.json

   # Windows (PowerShell)
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("keys\sa_key.json"))
   ```
4. Paste the output as the value of `GCP_CREDS` in `.env`

### 3 – Provision GCP infrastructure with Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # fill in your values
terraform init
terraform apply
cd ..
```

`terraform.tfvars` must contain your project ID and bucket name (same values as in `.env`).

### 4 – Start Kestra

```bash
cd kestra
docker compose up -d
```

Open [http://localhost:8080](http://localhost:8080) and log in with `KESTRA_USERNAME` / `KESTRA_PASSWORD` from your `.env`.

The `GCP_CREDS` value is pushed to the Kestra KV store in step 5 below.

### 5 – Populate the Kestra KV store

In the Kestra UI, execute flow **01_setup_kv** once. This stores project ID, bucket name and dataset names that all other flows reference.

Also update `GITHUB_REPO_URL` in `01_setup_kv.yaml` with your repository URL (needed for the dbt flow to clone the project).

### 6 – Run a historical backfill

Execute **04_backfill** with `start_date` and `end_date` to load historical data
(recommended: at least 30 days for meaningful dashboard charts).

Example: 30 days loads ~105M events (~3.5M events/day).

> **Estimated times** (each day has 24 hourly files, ~3.5M events):
>
> | Scope | Estimated time |
> |---|---|
> | 1 day (daily ingest) | ~8–10 min |
> | 7 days | ~1 hour |
> | 30 days (backfill) | ~3–4 hours |
>
> The backfill flow has a 6-hour timeout. For more than 30 days, split into multiple runs.
>
> **BigQuery free tier note:** the sandbox plan allows ~10 GB of active storage.
> 30 days of raw events approaches this limit — keep the backfill window within 30 days
> to avoid quota errors.

### 7 – Run dbt transformations

Execute **03_dbt_transform** manually (or wait — it triggers automatically after each daily ingest).
dbt clones the repo, runs all models and tests in ~3–5 minutes.

### 8 – Connect Looker Studio

1. Open [Looker Studio](https://lookerstudio.google.com) → Create → Report → BigQuery
2. Select project → `github_analytics_dwh` → `fct_daily_activity` → time-series line chart
3. Add a second data source → `fct_event_type_distribution` → bar chart

---

## BigQuery Table Design

### `github_archive_raw.events`

| Optimisation | Detail |
|---|---|
| **Partitioning** | `DAY` on `created_at` – queries filtered by date scan only relevant partitions |
| **Clustering** | `type`, `repo_name` – the two most common filter/group-by columns |

Querying a single day of data costs ~10× less than scanning the full table.

### dbt mart tables

| Table | Materialization | Purpose |
|---|---|---|
| `stg_github_events` | View | Cleaned staging layer |
| `fct_daily_activity` | Partitioned table | Temporal trend chart |
| `fct_event_type_distribution` | Table | Categorical distribution chart |
| `fct_top_repos` | View | Most active repositories |
