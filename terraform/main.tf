# Terraform configuration for AWS resources
#
# TODO: ensure all naming good
# Lambda exec policy name and group should be looked at again
# 
# ingest part built
# need to build the cloudwatch trigger
# build the pyspark side
provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

resource "random_id" "resource_suffix" {
  byte_length = 4
}

locals {
  project_root     = abspath("${path.root}/..")
  ingest_build_dir = "${path.root}/ingest/build"
}

# IAM role for Lambda execution
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "lambda_execution_policy" {
  statement {
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:GetObject",
      "s3:GetObjectAcl",
      "s3:AbortMultipartUpload",
      "s3:ListBucket"
    ]

    resources = [
      aws_s3_bucket.finance_data_bucket.arn,
      "${aws_s3_bucket.finance_data_bucket.arn}/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_role" "lambda_execution_role" {
  name_prefix        = "ingest-lambda-exec-${random_id.resource_suffix.hex}-"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy" "lambda_execution_role_policy" {
  name   = "lambda-execution-inline-policy"
  role   = aws_iam_role.lambda_execution_role.id
  policy = data.aws_iam_policy_document.lambda_execution_policy.json
}

resource "terraform_data" "build_ingest_lambda" {
  triggers_replace = {
    requirements_hash = filesha256("${local.project_root}/ingest_lambda/requirements.txt")
    package_script    = filesha256("${path.module}/package_ingest_lambda.sh")
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/package_ingest_lambda.sh"

    environment = {
      PROJECT_ROOT = local.project_root
      BUILD_DIR    = local.ingest_build_dir
    }
  }
}

# Package the Lambda function code
data "archive_file" "ingest_code" {
  type        = "zip"
  output_path = "${path.root}/ingest/ingest_lambda.zip"
  source_dir  = local.ingest_build_dir

  depends_on = [terraform_data.build_ingest_lambda]
}

# Lambda function ingest
resource "aws_lambda_function" "ingest_lambda" {
  filename      = data.archive_file.ingest_code.output_path
  function_name = "ingest_lambda_function"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "ingest.ingest_handler"
  code_sha256   = data.archive_file.ingest_code.output_base64sha256

  runtime = "python3.12"

  environment {
    variables = {
      ENVIRONMENT           = "production"
      LOG_LEVEL             = "INFO"
      ALPHA_VANTAGE_API_KEY = var.alpha_vantage_api_key
      FINANCE_DATA_BUCKET   = aws_s3_bucket.finance_data_bucket.bucket
    }
  }

  tags = {
    Environment = "production"
    Application = "finance-data-pipeline"
  }
}

// creat s3 bucket for lambda function
resource "aws_s3_bucket" "finance_data_bucket" {
  bucket = "finance-data-${data.aws_caller_identity.current.account_id}-${var.aws_region}-${random_id.resource_suffix.hex}"

  tags = {
    Name        = "Finance Bucket"
    Environment = "production"
  }
}
