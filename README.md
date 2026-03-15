# Finance Data Pipeline

Serverless AWS data pipeline that ingests stock market data, transforms it into a query-friendly curated layer, and makes it available through AWS Glue and Athena.

## What This Project Does

1. Ingests daily stock data from Alpha Vantage using an AWS Lambda function.
2. Stores raw JSON in Amazon S3 under a raw landing prefix.
3. Automatically triggers a second Lambda on new raw files.
4. Transforms nested JSON into typed tabular rows and writes Parquet to a curated S3 prefix partitioned by symbol, year, and month.
5. Registers partitions in AWS Glue Data Catalog.
6. Supports SQL querying via Amazon Athena.
7. Schedules ingestion every 12 hours with Amazon EventBridge.

## Architecture Overview

Data flow:

1. EventBridge rule invokes ingest Lambda on schedule.
2. Ingest Lambda calls Alpha Vantage API and writes raw data to S3:
	 - finance_data/daily/SYMBOL/oldest_to_newest.json
3. S3 object-created event triggers transform Lambda.
4. Transform Lambda flattens daily OHLCV data and writes curated Parquet:
	 - finance_data/curated/daily/symbol=SYMBOL/year=YYYY/month=MM/data.parquet
5. Transform Lambda creates Glue partitions for each symbol/year/month written.
6. Athena reads from Glue catalog table daily_prices.

## Tech Stack

- Language: Python 3.12
- Infrastructure as Code: Terraform
- AWS services:
	- AWS Lambda
	- Amazon S3
	- AWS Glue Data Catalog
	- Amazon Athena
	- Amazon EventBridge (CloudWatch Events)
	- AWS IAM
	- Amazon CloudWatch Logs
- Python libraries:
	- boto3
	- requests
	- pyarrow

## Project Structure

- ingest_lambda/ingest.py: raw ingestion Lambda.
- lambda/transform.py: transformation Lambda (raw JSON -> curated Parquet + Glue partitions).
- terraform/main.tf: core provider, S3 bucket, ingest Lambda, shared IAM setup.
- terraform/transform.tf: transform Lambda, IAM policy, and S3 notification trigger.
- terraform/analytics.tf: Glue database/table and Athena workgroup/resources.
- terraform/scheduler.tf: EventBridge ingestion schedule and Lambda invoke permission.
- terraform/variables.tf: configurable inputs (region, API key, schedule, symbol).
- terraform/outputs.tf: useful deployed outputs and sample Athena query.

## Prerequisites

- AWS account with permissions for Lambda, S3, Glue, Athena, IAM, EventBridge, and CloudWatch.
- AWS credentials configured locally (for example via AWS CLI profile (`aws configure`) or environment variables).
- Terraform >= 1.2.
- Python 3 and pip available on the machine running Terraform (used to package Lambda dependencies).
- Alpha Vantage API key.

## Configuration

Required variable:

- alpha_vantage_api_key

Optional variables (defaults in terraform/variables.tf):

- aws_region (default: us-west-2)
- ingest_symbol (default: IBM)
- ingest_schedule_expression (default: rate(12 hours))

Create a terraform.tfvars file in terraform/ with at least:

```hcl
alpha_vantage_api_key = "YOUR_ALPHA_VANTAGE_KEY"
# Optional overrides:
# aws_region = "us-west-2"
# ingest_symbol = "AAPL"
# ingest_schedule_expression = "rate(12 hours)"
```

## How To Run

Use the Terraform wrapper script in this repo. It loads environment variables
from `.env`, validates required `TF_VAR_*` settings, and runs Terraform with the
correct `-chdir` location.

From the repository root:

1. Create a `.env` file at repo root with at least:

```bash
TF_VAR_aws_region=us-west-2
TF_VAR_alpha_vantage_api_key=YOUR_ALPHA_VANTAGE_KEY
```

2. Initialize Terraform:

```bash
./terraform/tf-wrapper.sh init
```

3. Review changes:

```bash
./terraform/tf-wrapper.sh plan
```

4. Deploy resources:

```bash
./terraform/tf-wrapper.sh apply
```

5. View useful outputs:

```bash
./terraform/tf-wrapper.sh output
```

## How To Test End-to-End

After apply completes:

1. Wait for the EventBridge schedule to run ingest, or manually invoke the ingest Lambda from AWS Console.
2. Confirm raw object appears in the finance_data/daily/ prefix in S3.
3. Confirm curated Parquet appears in finance_data/curated/daily/symbol=.../year=.../month=.../.
4. Confirm Glue table and partitions exist (database: finance_data, table: daily_prices).
5. Run the sample query returned by Terraform output sample_athena_query in Athena.

## Notes

- The curated layout uses Hive-style partition folders (symbol=..., year=..., month=...) so Athena can prune partitions efficiently.
- Transform Lambda writes one Parquet object per symbol/year/month group for each processed raw file.
- Local editor warnings about pyarrow in lambda/transform.py are expected unless pyarrow is installed in your local Python environment; Terraform packaging installs it into the Lambda bundle.

## Cleanup

To remove all provisioned resources:

```bash
./terraform/tf-wrapper.sh destroy
```