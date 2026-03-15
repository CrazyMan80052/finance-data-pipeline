# Transform Lambda — IAM, packaging, function, and S3 trigger

locals {
  transform_build_dir = "${path.root}/transform/build"
}

# ─────────────────────────────────────────────
# IAM
# ─────────────────────────────────────────────

data "aws_iam_policy_document" "transform_execution_policy" {
  # Read raw JSON objects from the landing prefix
  statement {
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:GetObjectAcl"]
    resources = [
      "${aws_s3_bucket.finance_data_bucket.arn}/finance_data/daily/*",
    ]
  }

  # Write curated Parquet objects
  statement {
    effect  = "Allow"
    actions = ["s3:PutObject", "s3:PutObjectAcl", "s3:AbortMultipartUpload"]
    resources = [
      "${aws_s3_bucket.finance_data_bucket.arn}/finance_data/curated/*",
    ]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.finance_data_bucket.arn]
  }

  # Glue Data Catalog — partition management
  statement {
    effect = "Allow"
    actions = [
      "glue:GetDatabase",
      "glue:GetTable",
      "glue:CreatePartition",
      "glue:BatchCreatePartition",
      "glue:GetPartition",
      "glue:UpdatePartition",
    ]
    resources = [
      "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:catalog",
      "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:database/finance_data",
      "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/finance_data/daily_prices",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_role" "transform_lambda_role" {
  name_prefix        = "transform-lambda-exec-${random_id.resource_suffix.hex}-"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy" "transform_lambda_role_policy" {
  name   = "transform-lambda-inline-policy"
  role   = aws_iam_role.transform_lambda_role.id
  policy = data.aws_iam_policy_document.transform_execution_policy.json
}

# ─────────────────────────────────────────────
# Lambda packaging
# ─────────────────────────────────────────────

resource "terraform_data" "build_transform_lambda" {
  triggers_replace = {
    requirements_hash = filesha256("${local.project_root}/lambda/requirements.txt")
    package_script    = filesha256("${path.module}/package_transform_lambda.sh")
    source_hash       = filesha256("${local.project_root}/lambda/transform.py")
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/package_transform_lambda.sh"

    environment = {
      PROJECT_ROOT = local.project_root
      BUILD_DIR    = local.transform_build_dir
    }
  }
}

data "archive_file" "transform_code" {
  type        = "zip"
  output_path = "${path.root}/transform/transform_lambda.zip"
  source_dir  = local.transform_build_dir

  depends_on = [terraform_data.build_transform_lambda]
}

# ─────────────────────────────────────────────
# Lambda function
# ─────────────────────────────────────────────

resource "aws_lambda_function" "transform_lambda" {
  filename      = data.archive_file.transform_code.output_path
  function_name = "transform_lambda_function"
  role          = aws_iam_role.transform_lambda_role.arn
  handler       = "transform.transform_handler"
  code_sha256   = data.archive_file.transform_code.output_base64sha256

  runtime     = "python3.12"
  timeout     = 120
  memory_size = 512

  environment {
    variables = {
      LOG_LEVEL      = "INFO"
      GLUE_DATABASE  = aws_glue_catalog_database.finance_data.name
      GLUE_TABLE     = aws_glue_catalog_table.daily_prices.name
      CURATED_PREFIX = "finance_data/curated/daily"
    }
  }

  tags = {
    Environment = "production"
    Application = "finance-data-pipeline"
  }

  depends_on = [aws_glue_catalog_table.daily_prices]
}

# ─────────────────────────────────────────────
# S3 → Lambda trigger
# ─────────────────────────────────────────────

# Grants S3 permission to invoke the transform Lambda
resource "aws_lambda_permission" "allow_s3_transform" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.transform_lambda.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.finance_data_bucket.arn
}

# Fires whenever a new raw JSON file is placed under finance_data/daily/
resource "aws_s3_bucket_notification" "raw_object_created" {
  bucket = aws_s3_bucket.finance_data_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.transform_lambda.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "finance_data/daily/"
    filter_suffix       = ".json"
  }

  depends_on = [aws_lambda_permission.allow_s3_transform]
}
