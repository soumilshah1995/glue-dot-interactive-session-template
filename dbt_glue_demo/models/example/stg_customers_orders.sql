{{ config(
    materialized='incremental',
    file_format='parquet',
    incremental_strategy='insert_overwrite',
) }}

WITH
stg_customers AS (
    SELECT
        customer_id,
        name AS customer_name,
        city,
        email,
        created_at AS customer_created_at,
        address,
        state
    FROM {{ source('data_source', 'customers') }}
),

stg_orders AS (
    SELECT
      order_id,
      product_id AS order_name,
      total_price AS order_value,
      CAST(NULL AS STRING) as priority, -- Replace null with a placeholder
      order_date,
      customer_id
    FROM {{ source('data_source', 'orders') }}
)

SELECT
    c.customer_id,
    c.customer_name,
    c.city,
    c.email,
    c.customer_created_at,
    c.address,
    c.state,
    o.order_id,
    o.order_name,
    o.order_value,
    o.priority,
    o.order_date
FROM
    stg_customers c
        JOIN
    stg_orders o
    ON
            c.customer_id = o.customer_id;
