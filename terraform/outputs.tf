output "finance_data_bucket" {
  description = "S3 bucket holding raw and curated finance data"
  value       = aws_s3_bucket.finance_data_bucket.bucket
}

output "athena_query_results_bucket" {
  description = "S3 bucket for Athena query results"
  value       = aws_s3_bucket.athena_query_results.bucket
}

output "glue_database" {
  description = "AWS Glue catalog database name"
  value       = aws_glue_catalog_database.finance_data.name
}

output "glue_table" {
  description = "AWS Glue catalog table name for daily prices"
  value       = aws_glue_catalog_table.daily_prices.name
}

output "athena_workgroup" {
  description = "Athena workgroup for querying finance data"
  value       = aws_athena_workgroup.finance.name
}

output "ingest_lambda_name" {
  description = "Name of the ingestion Lambda function"
  value       = aws_lambda_function.ingest_lambda.function_name
}

output "transform_lambda_name" {
  description = "Name of the transform Lambda function"
  value       = aws_lambda_function.transform_lambda.function_name
}

output "sample_athena_query" {
  description = "Example Athena query to verify the pipeline end-to-end"
  value       = <<-EOT
    SELECT symbol, trading_date, open, high, low, close, volume
    FROM ${aws_glue_catalog_database.finance_data.name}.${aws_glue_catalog_table.daily_prices.name}
    WHERE symbol = '${var.ingest_symbol}'
    ORDER BY trading_date DESC
    LIMIT 20;
  EOT
}
