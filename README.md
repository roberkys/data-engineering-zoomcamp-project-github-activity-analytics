# GitHub Activity Analytics Dashboard

An end-to-end data pipeline that ingests **GitHub Archive** event data into BigQuery,
transforms it with dbt, and visualises it in a Looker Studio dashboard.

Built as the final project for the [Data Engineering Zoomcamp](https://github.com/DataTalksClub/data-engineering-zoomcamp).

---

## Problem Statement

GitHub is the world's largest software collaboration platform, generating over **3.5 million public
events every day** — pushes, pull requests, issues, forks, code reviews, and more.
Understanding these patterns is valuable for engineering leaders, developer tools companies,
and open-source maintainers who want to answer questions like:

- Is developer activity growing or shrinking over time?
- Which event types drive the most volume — and which are underrepresented?
- What does a "normal" day of GitHub activity look like, and what are the outliers?

This project builds a fully automated pipeline that ingests the
[GitHub Archive](https://www.gharchive.org/) — a public record of every GitHub event since 2011 —
into a partitioned BigQuery data warehouse, transforms it with dbt, and surfaces the answers
in an interactive Looker Studio dashboard with two analytical tiles:

1. **How has GitHub activity trended over time?** (temporal distribution by event type)
2. **What types of events dominate developer activity?** (categorical share across all events)

---

## Architecture

```
GH Archive (hourly JSON.gz files at gharchive.org)
        │
        ▼
[Kestra] 02_ingest flow (daily schedule 07:00 UTC)
  • Downloads 24 hourly files for the previous day
  • Flattens nested JSON → 8-field rows
  • Loads directly into BigQuery via load_table_from_json
        │
        ▼
BigQuery: github_archive_raw.events
  (partitioned by DAY on created_at, clustered by type + repo_name)
        │
        ▼
[dbt] 03_dbt_transform flow (auto-triggered after each ingest)
  • stg_github_events          (view, deduplicated)
  • fct_daily_activity         (partitioned table — powers tile 1)
  • fct_event_type_distribution(table — powers tile 2)
  • fct_top_repos              (view — leaderboard / drill-down)
        │
        ▼
BigQuery: github_analytics_dwh.*
        │
        ▼
Looker Studio Dashboard (2 tiles)
```

## Architecture Notes

**Why no GCS data lake?**
The pipeline loads GitHub Archive data directly from the source into BigQuery, skipping a GCS staging layer.
This is intentional: the GCP project runs on the free sandbox tier which does not support GCS bucket creation.
Direct-to-BigQuery loading via the `load_table_from_json` API is a valid and increasingly common pattern —
it reduces latency, eliminates an extra storage cost, and simplifies the pipeline without sacrificing reliability.
The raw `events` table in BigQuery serves as the durable, queryable landing zone (equivalent to a data lake layer).

---

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
│   ├── main.tf           # BigQuery datasets and raw events table
│   └── variables.tf
│
├── kestra/
│   ├── docker-compose.yml
│   └── flows/
│       ├── 01_setup_kv.yaml      # One-time KV store setup
│       ├── 02_ingest.yaml        # Daily ingest: GH Archive → BigQuery
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

- GCP project with BigQuery API enabled
- Terraform ≥ 1.5
- Docker + Docker Compose

### 1 – Clone the repo

```bash
git clone https://github.com/roberkys/data-engineering-zoomcamp-project-github-activity-analytics.git
cd data-engineering-zoomcamp-project-github-activity-analytics
```

### 2 – Create a GCP service account

1. In the GCP Console, create a service account with the role **BigQuery Admin**
2. Download the JSON key → save as `keys/sa_key.json`

### 3 – Configure environment variables

```bash
cp .env.example .env
```

Edit `.env` and fill in:

| Variable | Description |
|---|---|
| `GCP_PROJECT_ID` | Your GCP project ID |
| `GCP_LOCATION` | BigQuery location (e.g. `US`) |
| `KESTRA_USERNAME` | Kestra UI login (default: `admin@kestra.io`) |
| `KESTRA_PASSWORD` | Kestra UI password (default: `Admin1234!`) |

### 4 – Provision GCP infrastructure with Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # fill in your project ID
terraform init
terraform apply
cd ..
```

This creates the `github_archive_raw` and `github_analytics_dwh` BigQuery datasets,
and the partitioned + clustered `events` table.

### 5 – Start Kestra

```bash
cd kestra
docker compose up -d
```

Open [http://localhost:8080](http://localhost:8080) and log in with your credentials from `.env`.

### 6 – Populate the Kestra KV store

The flows read all configuration from Kestra's KV store. Populate it in two steps:

**a) Push your GCP credentials** (replace the path if needed):

```bash
curl -X PUT \
  -u "admin@kestra.io:Admin1234!" \
  -H "Content-Type: application/json" \
  -d "$(cat keys/sa_key.json | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')" \
  "http://localhost:8080/api/v1/namespaces/github_analytics/kv/GCP_CREDS"
```

**b) Update `01_setup_kv.yaml`** — set `GITHUB_REPO_URL` to your forked repo URL, then import and run the flow in the Kestra UI. This sets all remaining KV values (project ID, dataset names, etc.).

### 7 – Run a historical backfill

Execute flow **04_backfill** with `start_date` and `end_date` to load historical data
(recommended: at least 30 days for meaningful dashboard charts).

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

### 8 – Run dbt transformations

Execute flow **03_dbt_transform** manually (or wait — it triggers automatically after each daily ingest).
dbt clones the repo, runs all models and tests in ~3–5 minutes.

### 9 – Connect Looker Studio

1. Open [Looker Studio](https://lookerstudio.google.com) → Create → Report → BigQuery
2. Select project → `github_analytics_dwh` → `fct_daily_activity` → time-series line chart
   - Dimension: `event_date`, Metric: `event_count`, Breakdown: `event_type`
3. Add a second chart → `fct_event_type_distribution` → bar chart
   - Dimension: `event_type`, Metric: `pct_of_total`

---

## BigQuery Table Design

### `github_archive_raw.events`

| Optimisation | Detail |
|---|---|
| **Partitioning** | `DAY` on `created_at` — queries filtered by date scan only relevant partitions |
| **Clustering** | `type`, `repo_name` — the two most common filter/group-by columns |

Querying a single day of data costs ~10× less than scanning the full table.
The dbt mart `fct_daily_activity` is also partitioned by `event_date` and clustered by `event_type`,
so dashboard queries that filter by date or event type benefit from both optimisations.

### dbt mart tables

| Table | Materialization | Purpose |
|---|---|---|
| `stg_github_events` | View | Cleaned, deduplicated staging layer |
| `fct_daily_activity` | Partitioned table | Temporal trend chart (tile 1) |
| `fct_event_type_distribution` | Table | Categorical distribution chart (tile 2) |
| `fct_top_repos` | View | Most active repositories leaderboard |
