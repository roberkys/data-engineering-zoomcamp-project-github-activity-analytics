{{
    config(
        materialized = 'view'
    )
}}

select
    id                                          as event_id,
    type                                        as event_type,
    created_at                                  as event_timestamp,
    date(created_at)                            as event_date,
    public                                      as is_public,
    actor_login,
    actor_id,
    repo_name,
    repo_id,
    split(repo_name, '/')[safe_offset(0)]       as repo_owner,
    split(repo_name, '/')[safe_offset(1)]       as repo_short_name

from {{ source('github_archive_raw', 'events') }}

where
    created_at is not null
    and type is not null

qualify row_number() over (partition by id order by created_at) = 1
