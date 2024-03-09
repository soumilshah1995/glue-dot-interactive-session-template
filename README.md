# glue-dot-interactive-session-template
glue-dot-interactive-session-template
![Screenshot 2024-03-09 at 9 16 43 AM](https://github.com/soumilshah1995/glue-dot-interactive-session-template/assets/39345855/be7b23c3-db67-494d-82c7-8112a0cae9e0)


# Steps


### Step 1: Deploy the Stack and copy ARN
```
cd infra
sls deploy
```

### Step 2: Create Virtual ENV for DBT projects
```
python -m venv dbt-env
source dbt-env/bin/activate
pip3 install --no-cache-dir dbt-core
pip3 install --no-cache-dir dbt-glue
```

# Step 3: Create DBT project
```
dbt init
project_name : dbt_glue_demo
cd dbt_glue_demo
rm -r seeds tests macros analyses snapshots models
mkdir models
cd models
nano source.yml
```

#### Tables you want to use to join etc for your projects 
```
version: 2
sources:
  - name: data_source
    schema: default
    tables:
      - name: orders
      - name: customers
```

### Create Models and define your SQL there
```
mkdirs example
cd example
nano stg_customers_orders.sql
```


### Your SQL query goes inside this file 

```
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

```

#create profiles

nano profiles.yml

```
connections:
<CHANGE>:
  outputs:
    dev:
      type: glue
      role_arn: arn:aws:iam::<ACCOUNT>:role/GlueInteractiveSessionRole
      region: us-east-1
      workers: 3
      worker_type: G.1X
      schema: "default"
      session_provisioning_timeout_in_seconds: 200
      glue_session_reuse: True
      datalake_formats: "hudi"
      location: "s3://<BUCKET>/dbt/"
      conf: spark.serializer=org.apache.spark.serializer.KryoSerializer  --conf spark.sql.hive.convertMetastoreParquet=false --conf spark.sql.hive.convertMetastoreParquet=false --conf spark.sql.catalog.spark_catalog=org.apache.spark.sql.hudi.catalog.HoodieCatalog --conf spark.sql.legacy.pathOptionBehavior.enabled=true --conf spark.sql.extensions=org.apache.spark.sql.hudi.HoodieSparkSessionExtension

  target: dev
```

### Folder looks like 

![Screenshot 2024-03-09 at 10 17 11 AM](https://github.com/soumilshah1995/glue-dot-interactive-session-template/assets/39345855/fcd89d3c-6bb7-49d5-88c3-93960cf84d05)


### Run DBT projects
```
dbt debug \
--profiles-dir <PATH>

dbt run \
--profiles-dir <>
```
