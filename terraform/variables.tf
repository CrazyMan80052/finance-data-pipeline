variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "alpha_vantage_api_key" {
  type = string
}

variable "s3_bucket_name" {
  type    = string
  default = "finance-data-bucket"
}

variable "ingest_symbol" {
  description = "Stock ticker symbol passed to the ingest Lambda on each scheduled run (e.g. IBM, AAPL)"
  type        = string
  default     = "IBM"
}

variable "ingest_schedule_expression" {
  description = "EventBridge schedule expression controlling how often the ingest Lambda runs"
  type        = string
  default     = "rate(12 hours)"
}
