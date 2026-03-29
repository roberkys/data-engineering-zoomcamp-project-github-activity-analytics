{{
    config(
        materialized = 'view'
    )
}}

/*
  Most active repositories by event type.
  Useful for a leaderboard tile or filtered drill-down.
*/

select
    repo_name,
    repo_owner,
    event_type,
    count(*)                    as event_count,
    count(distinct actor_login) as unique_contributors,
    min(event_date)             as first_activity_date,
    max(event_date)             as last_activity_date

from {{ ref('stg_github_events') }}

where repo_name is not null

group by 1, 2, 3
having count(*) > 5
