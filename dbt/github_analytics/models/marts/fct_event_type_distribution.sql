{{
    config(
        materialized = 'table'
    )
}}

/*
  Total event counts per event type across the full dataset.
  Powers the categorical bar/pie chart on the dashboard:
    X-axis / slice: event_type   Y-axis / value: total_events or percentage
*/

select
    event_type,
    count(*)                                                        as total_events,
    round(100.0 * count(*) / sum(count(*)) over (), 2)             as pct_of_total,
    count(distinct actor_login)                                     as unique_actors,
    count(distinct repo_name)                                       as unique_repos,
    min(event_date)                                                 as first_seen_date,
    max(event_date)                                                 as last_seen_date

from {{ ref('stg_github_events') }}

group by 1
order by 2 desc
