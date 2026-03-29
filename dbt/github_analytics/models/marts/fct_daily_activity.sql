{{
    config(
        materialized = 'table',
        partition_by = {
            'field': 'event_date',
            'data_type': 'date',
            'granularity': 'day'
        },
        cluster_by = ['event_type']
    )
}}

/*
  Daily GitHub activity broken down by event type.
  Powers the temporal line chart on the dashboard:
    X-axis: event_date   Y-axis: event_count   Series: event_type
*/

select
    event_date,
    event_type,
    count(*)                    as event_count,
    count(distinct actor_login) as unique_actors,
    count(distinct repo_name)   as unique_repos

from {{ ref('stg_github_events') }}

group by 1, 2
