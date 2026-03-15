# Finance Data Pipeline Project Plan

## Project Goal

Build a **serverless ETL pipeline** that collects stock market data, cleans and transforms it using PySpark, stores optimized data in S3 using Parquet format, and allows fast querying with Athena. The pipeline runs automatically every 12 hours and is deployed using Infrastructure as Code.

---

# Technologies Used

## Programming
- Python
- PySpark
- SQL

## AWS Services
- AWS Lambda
- Amazon S3
- Amazon Athena
- AWS Glue (Data Catalog)
- CloudWatch (scheduling + logs)
- IAM (permissions)

## Infrastructure as Code
- Terraform

## Data Formats
- JSON or CSV (raw data)
- Parquet (processed data)

---

# High Level Architecture
