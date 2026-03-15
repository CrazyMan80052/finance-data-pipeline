# Analytics layer — Glue Data Catalog and Athena workgroup

# ─────────────────────────────────────────────
# Glue Data Catalog
# ─────────────────────────────────────────────

resource "aws_glue_catalog_database" "finance_data" {
  name        = "finance_data"
  description = "Curated finance data for the AWS finance data pipeline"

  tags = {
    Environment = "production"
    Application = "finance-data-pipeline"
  }
}

resource "aws_glue_catalog_table" "daily_prices" {
  name          = "daily_prices"
  database_name = aws_glue_catalog_database.finance_data.name
  description   = "Daily OHLCV prices, partitioned by symbol/year/month, stored as Parquet"
  table_type    = "EXTERNAL_TABLE"

  # Hive-style partition keys — Athena prunes on these without scanning all data
  partition_keys {
    name    = "symbol"
    type    = "string"
    comment = "Stock ticker symbol (e.g. IBM)"
  }
  partition_keys {
    name    = "year"
    type    = "string"
    comment = "Calendar year of the trading date (YYYY)"
  }
  partition_keys {
    name    = "month"
    type    = "string"
    comment = "Calendar month of the trading date (MM, zero-padded)"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.finance_data_bucket.bucket}/finance_data/curated/daily"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" = "1"
      }
    }

    columns {
      name    = "trading_date"
      type    = "string"
      comment = "Trading date (YYYY-MM-DD)"
    }
    columns {
      name    = "open"
      type    = "double"
      comment = "Opening price"
    }
    columns {
      name    = "high"
      type    = "double"
      comment = "Highest price of the day"
    }
    columns {
      name    = "low"
      type    = "double"
      comment = "Lowest price of the day"
    }
    columns {
      name    = "close"
      type    = "double"
      comment = "Closing price"
    }
    columns {
      name    = "volume"
      type    = "bigint"
      comment = "Number of shares traded"
    }
    columns {
      name    = "ingested_at"
      type    = "string"
      comment = "ISO-8601 UTC timestamp of when the raw file was ingested"
    }
  }

  parameters = {
    classification = "parquet"
  }
}

# ─────────────────────────────────────────────
# Athena
# ─────────────────────────────────────────────

resource "aws_s3_bucket" "athena_query_results" {
  bucket = "finance-athena-${data.aws_caller_identity.current.account_id}-${var.aws_region}-${random_id.resource_suffix.hex}"

  tags = {
    Name        = "Athena Query Results"
    Environment = "production"
    Application = "finance-data-pipeline"
  }
}

resource "aws_athena_workgroup" "finance" {
  name        = "finance-analytics"
  description = "Query the finance data pipeline curated layer"

  configuration {
    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_query_results.bucket}/query-results/"
    }
  }

  tags = {
    Environment = "production"
    Application = "finance-data-pipeline"
  }
}
