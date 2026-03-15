import io
import json
import logging
import os
from datetime import datetime, timezone
from urllib.parse import unquote_plus

import boto3
import pyarrow as pa
import pyarrow.parquet as pq

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

s3_client = boto3.client("s3")
glue_client = boto3.client("glue")

# Schema for the curated Parquet files.
# 'symbol' is omitted here because it is a Hive partition key; Athena
# reconstructs it from the S3 path automatically.
_SCHEMA = pa.schema([
    pa.field("trading_date", pa.string()),
    pa.field("open", pa.float64()),
    pa.field("high", pa.float64()),
    pa.field("low", pa.float64()),
    pa.field("close", pa.float64()),
    pa.field("volume", pa.int64()),
    pa.field("ingested_at", pa.string()),
])


def flatten_daily_data(raw: dict) -> tuple[list[dict], str]:
    """Flatten the Alpha Vantage Time Series (Daily) envelope into rows."""
    meta = raw.get("Meta Data", {})
    symbol = meta.get("2. Symbol", "UNKNOWN")
    time_series = raw.get("Time Series (Daily)", {})
    ingested_at = datetime.now(tz=timezone.utc).isoformat()

    rows = []
    for date_str, values in time_series.items():
        rows.append({
            "trading_date": date_str,
            "open": float(values["1. open"]),
            "high": float(values["2. high"]),
            "low": float(values["3. low"]),
            "close": float(values["4. close"]),
            "volume": int(values["5. volume"]),
            "ingested_at": ingested_at,
        })
    return rows, symbol


def group_by_year_month(rows: list[dict]) -> dict[tuple, list[dict]]:
    """Split rows into groups keyed by (year, month) for Hive partitioning."""
    groups: dict[tuple, list[dict]] = {}
    for row in rows:
        year, month = row["trading_date"].split("-")[:2]
        groups.setdefault((year, month), []).append(row)
    return groups


def write_parquet_to_s3(bucket: str, key: str, rows: list[dict]) -> None:
    table = pa.Table.from_pylist(rows, schema=_SCHEMA)
    buf = io.BytesIO()
    pq.write_table(table, buf)
    buf.seek(0)
    s3_client.put_object(Bucket=bucket, Key=key, Body=buf.read())
    logger.info("Wrote %d rows to s3://%s/%s", len(rows), bucket, key)


def ensure_glue_partition(
    database: str,
    table_name: str,
    symbol: str,
    year: str,
    month: str,
    bucket: str,
    partition_prefix: str,
) -> None:
    location = f"s3://{bucket}/{partition_prefix}"
    try:
        glue_client.create_partition(
            DatabaseName=database,
            TableName=table_name,
            PartitionInput={
                "Values": [symbol, year, month],
                "StorageDescriptor": {
                    "Location": location,
                    "InputFormat": "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat",
                    "OutputFormat": "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat",
                    "SerdeInfo": {
                        "SerializationLibrary": "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe",
                    },
                },
            },
        )
        logger.info("Created Glue partition: symbol=%s/year=%s/month=%s", symbol, year, month)
    except glue_client.exceptions.AlreadyExistsException:
        logger.debug("Glue partition already exists: symbol=%s/year=%s/month=%s", symbol, year, month)


def transform_handler(event, context):
    """
    Transform Lambda handler.
    Triggered by S3 object-created events on the raw prefix.
    Reads raw Alpha Vantage JSON, flattens it to rows, writes Parquet
    partitioned by symbol/year/month to the curated prefix, and registers
    each new partition in the Glue Data Catalog.
    """
    glue_database = os.environ["GLUE_DATABASE"]
    glue_table = os.environ["GLUE_TABLE"]
    curated_prefix = os.environ.get("CURATED_PREFIX", "finance_data/curated/daily")

    for record in event["Records"]:
        bucket = record["s3"]["bucket"]["name"]
        raw_key = unquote_plus(record["s3"]["object"]["key"])
        logger.info("Processing raw file: s3://%s/%s", bucket, raw_key)

        response = s3_client.get_object(Bucket=bucket, Key=raw_key)
        raw = json.loads(response["Body"].read())

        rows, symbol = flatten_daily_data(raw)
        if not rows:
            logger.warning("No rows extracted from %s; skipping", raw_key)
            continue

        groups = group_by_year_month(rows)
        total_rows = 0

        for (year, month), month_rows in groups.items():
            partition_prefix = f"{curated_prefix}/symbol={symbol}/year={year}/month={month}"
            parquet_key = f"{partition_prefix}/data.parquet"
            write_parquet_to_s3(bucket, parquet_key, month_rows)
            ensure_glue_partition(
                glue_database, glue_table, symbol, year, month, bucket, partition_prefix
            )
            total_rows += len(month_rows)

        logger.info(
            "Transform complete for %s: %d rows across %d partitions",
            symbol, total_rows, len(groups),
        )

    return {"statusCode": 200, "message": "Transform complete"}
