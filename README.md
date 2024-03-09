
glue-dot-interactive-session-template
![Screenshot 2024-03-09 at 9 16 43 AM](https://github.com/soumilshah1995/glue-dot-interactive-session-template/assets/39345855/be7b23c3-db67-494d-82c7-8112a0cae9e0)


# Steps

### Sample code to create 2 hudi tables customers and orders 
```
try:
    import sys, random, uuid
    from pyspark.context import SparkContext
    from pyspark.sql.session import SparkSession
    from awsglue.context import GlueContext
    from awsglue.job import Job
    from awsglue.dynamicframe import DynamicFrame
    from pyspark.sql.functions import col, to_timestamp, monotonically_increasing_id, to_date, when
    from pyspark.sql.functions import *
    from awsglue.utils import getResolvedOptions
    from pyspark.sql.types import *
    from datetime import datetime, date
    import boto3, pandas
    from functools import reduce
    from pyspark.sql import Row
    from faker import Faker
except Exception as e:
    print("Modules are missing : {} ".format(e))

job_start_ts = datetime.now()
ts_format = '%Y-%m-%d %H:%M:%S'

spark = (SparkSession.builder.config('spark.serializer', 'org.apache.spark.serializer.KryoSerializer') \
         .config('spark.sql.hive.convertMetastoreParquet', 'false') \
         .config('spark.sql.catalog.spark_catalog', 'org.apache.spark.sql.hudi.catalog.HoodieCatalog') \
         .config('spark.sql.extensions', 'org.apache.spark.sql.hudi.HoodieSparkSessionExtension') \
         .config('spark.sql.legacy.pathOptionBehavior.enabled', 'true').getOrCreate())

sc = spark.sparkContext
glueContext = GlueContext(sc)
job = Job(glueContext)
logger = glueContext.get_logger()


def upsert_hudi_table(glue_database, table_name, record_id, precomb_key, table_type, spark_df, partition_fields,
                      enable_partition, enable_cleaner, enable_hive_sync, enable_clustering,
                      enable_meta_data_indexing,
                      use_sql_transformer, sql_transformer_query,
                      target_path, index_type, method='upsert', clustering_column='default'):
    """
    Upserts a dataframe into a Hudi table.

    Args:
        glue_database (str): The name of the glue database.
        table_name (str): The name of the Hudi table.
        record_id (str): The name of the field in the dataframe that will be used as the record key.
        precomb_key (str): The name of the field in the dataframe that will be used for pre-combine.
        table_type (str): The Hudi table type (e.g., COPY_ON_WRITE, MERGE_ON_READ).
        spark_df (pyspark.sql.DataFrame): The dataframe to upsert.
        partition_fields this is used to parrtition data
        enable_partition (bool): Whether or not to enable partitioning.
        enable_cleaner (bool): Whether or not to enable data cleaning.
        enable_hive_sync (bool): Whether or not to enable syncing with Hive.
        use_sql_transformer (bool): Whether or not to use SQL to transform the dataframe before upserting.
        sql_transformer_query (str): The SQL query to use for data transformation.
        target_path (str): The path to the target Hudi table.
        method (str): The Hudi write method to use (default is 'upsert').
        index_type : BLOOM or GLOBAL_BLOOM
    Returns:
        None
    """
    # These are the basic settings for the Hoodie table
    hudi_final_settings = {
        "hoodie.table.name": table_name,
        "hoodie.datasource.write.table.type": table_type,
        "hoodie.datasource.write.operation": method,
        "hoodie.datasource.write.recordkey.field": record_id,
        "hoodie.datasource.write.precombine.field": precomb_key,
    }

    # These settings enable syncing with Hive
    hudi_hive_sync_settings = {
        "hoodie.parquet.compression.codec": "gzip",
        "hoodie.datasource.hive_sync.enable": "true",
        "hoodie.datasource.hive_sync.database": glue_database,
        "hoodie.datasource.hive_sync.table": table_name,
        "hoodie.datasource.hive_sync.partition_extractor_class": "org.apache.hudi.hive.MultiPartKeysValueExtractor",
        "hoodie.datasource.hive_sync.use_jdbc": "false",
        "hoodie.datasource.hive_sync.mode": "hms",
    }

    # These settings enable automatic cleaning of old data
    hudi_cleaner_options = {
        "hoodie.clean.automatic": "true",
        "hoodie.clean.async": "true",
        "hoodie.cleaner.policy": 'KEEP_LATEST_FILE_VERSIONS',
        "hoodie.cleaner.fileversions.retained": "3",
        "hoodie-conf hoodie.cleaner.parallelism": '200',
        'hoodie.cleaner.commits.retained': 5
    }

    # These settings enable partitioning of the data
    partition_settings = {
        "hoodie.datasource.write.partitionpath.field": partition_fields,
        "hoodie.datasource.hive_sync.partition_fields": partition_fields,
        "hoodie.datasource.write.hive_style_partitioning": "true",
    }

    hudi_clustering = {
        "hoodie.clustering.execution.strategy.class": "org.apache.hudi.client.clustering.run.strategy.SparkSortAndSizeExecutionStrategy",
        "hoodie.clustering.inline": "true",
        "hoodie.clustering.plan.strategy.sort.columns": clustering_column,
        "hoodie.clustering.plan.strategy.target.file.max.bytes": "1073741824",
        "hoodie.clustering.plan.strategy.small.file.limit": "629145600"
    }

    # Define a dictionary with the index settings for Hudi
    hudi_index_settings = {
        "hoodie.index.type": index_type,  # Specify the index type for Hudi
    }

    # Define a dictionary with the Fiel Size
    hudi_file_size = {
        "hoodie.parquet.max.file.size": 512 * 1024 * 1024,  # 512MB
        "hoodie.parquet.small.file.limit": 104857600,  # 100MB
    }

    hudi_meta_data_indexing = {
        "hoodie.metadata.enable": "true",
        "hoodie.metadata.index.async": "true",
        "hoodie.metadata.index.column.stats.enable": "true",
        "hoodie.metadata.index.check.timeout.seconds": "60",
        "hoodie.write.concurrency.mode": "optimistic_concurrency_control",
        "hoodie.write.lock.provider": "org.apache.hudi.client.transaction.lock.InProcessLockProvider"
    }

    if enable_meta_data_indexing == True or enable_meta_data_indexing == "True" or enable_meta_data_indexing == "true":
        for key, value in hudi_meta_data_indexing.items():
            hudi_final_settings[key] = value  # Add the key-value pair to the final settings dictionary

    if enable_clustering == True or enable_clustering == "True" or enable_clustering == "true":
        for key, value in hudi_clustering.items():
            hudi_final_settings[key] = value  # Add the key-value pair to the final settings dictionary

    # Add the Hudi index settings to the final settings dictionary
    for key, value in hudi_index_settings.items():
        hudi_final_settings[key] = value  # Add the key-value pair to the final settings dictionary

    for key, value in hudi_file_size.items():
        hudi_final_settings[key] = value  # Add the key-value pair to the final settings dictionary

    # If partitioning is enabled, add the partition settings to the final settings
    if enable_partition == "True" or enable_partition == "true" or enable_partition == True:
        for key, value in partition_settings.items(): hudi_final_settings[key] = value

    # If data cleaning is enabled, add the cleaner options to the final settings
    if enable_cleaner == "True" or enable_cleaner == "true" or enable_cleaner == True:
        for key, value in hudi_cleaner_options.items(): hudi_final_settings[key] = value

    # If Hive syncing is enabled, add the Hive sync settings to the final settings
    if enable_hive_sync == "True" or enable_hive_sync == "true" or enable_hive_sync == True:
        for key, value in hudi_hive_sync_settings.items(): hudi_final_settings[key] = value

    # If there is data to write, apply any SQL transformations and write to the target path
    if spark_df.count() > 0:
        if use_sql_transformer == "True" or use_sql_transformer == "true" or use_sql_transformer == True:
            spark_df.createOrReplaceTempView("temp")
            spark_df = spark.sql(sql_transformer_query)

        spark_df.write.format("hudi"). \
            options(**hudi_final_settings). \
            mode("append"). \
            save(target_path)

# Define static mock data for customers
customers_data = [
    ("1", "John Doe", "New York", "john@example.com", "2022-01-01", "123 Main St", "NY"),
    ("2", "Jane Smith", "Los Angeles", "jane@example.com", "2022-01-02", "456 Elm St", "CA"),
    ("3", "Alice Johnson", "Chicago", "alice@example.com", "2022-01-03", "789 Oak St", "IL")
]

# Define schema for customers data
customers_schema = StructType([
    StructField("customer_id", StringType(), nullable=False),
    StructField("name", StringType(), nullable=True),
    StructField("city", StringType(), nullable=False),
    StructField("email", StringType(), nullable=False),
    StructField("created_at", StringType(), nullable=False),
    StructField("address", StringType(), nullable=False),
    StructField("state", StringType(), nullable=False)
])

# Create DataFrame for customers
customers_df = spark.createDataFrame(data=customers_data, schema=customers_schema)

# Define static mock data for orders
orders_data = [
    ("101", "1", "P123", "2", "45.99", "2022-01-02"),
    ("102", "1", "P456", "1", "29.99", "2022-01-03"),
    ("103", "2", "P789", "3", "99.99", "2022-01-01"),
    ("104", "3", "P123", "1", "49.99", "2022-01-02")
]

# Define schema for orders data
orders_schema = StructType([
    StructField("order_id", StringType(), nullable=False),
    StructField("customer_id", StringType(), nullable=False),
    StructField("product_id", StringType(), nullable=False),
    StructField("quantity", StringType(), nullable=False),
    StructField("total_price", StringType(), nullable=False),
    StructField("order_date", StringType(), nullable=False)
])

# Create DataFrame for orders
orders_df = spark.createDataFrame(data=orders_data, schema=orders_schema)

# Show the generated DataFrames
customers_df.show()
orders_df.show()
BUCKET = "soumil-dev-bucket-1995"


upsert_hudi_table(
    glue_database="default",
    table_name="customers",
    record_id="customer_id",
    precomb_key="created_at",
    table_type='COPY_ON_WRITE',
    partition_fields="state",
    method='upsert',
    index_type='BLOOM',
    enable_partition=True,
    enable_cleaner=False,
    enable_hive_sync=True,
    enable_clustering='False',
    clustering_column='default',
    enable_meta_data_indexing='false',
    use_sql_transformer=False,
    sql_transformer_query='default',
    target_path=f"s3://{BUCKET}/silver/table_name=customers/",
    spark_df=customers_df,
)

upsert_hudi_table(
    glue_database="default",
    table_name="orders",
    record_id="order_id",
    precomb_key="order_date",
    table_type='COPY_ON_WRITE',
    partition_fields="default",
    method='upsert',
    index_type='BLOOM',
    enable_partition=False,
    enable_cleaner=False,
    enable_hive_sync=True,
    enable_clustering='False',
    clustering_column='default',
    enable_meta_data_indexing='false',
    use_sql_transformer=False,
    sql_transformer_query='default',
    target_path=f"s3://{BUCKET}/silver/table_name=orders/",
    spark_df=orders_df,
)

```
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
