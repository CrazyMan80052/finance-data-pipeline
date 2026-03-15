# Scheduler — EventBridge rule that invokes the ingest Lambda on a cron schedule

resource "aws_cloudwatch_event_rule" "ingest_schedule" {
  name                = "ingest-schedule-${random_id.resource_suffix.hex}"
  description         = "Triggers the ingest Lambda on a recurring schedule"
  schedule_expression = var.ingest_schedule_expression
}

resource "aws_cloudwatch_event_target" "ingest_lambda_target" {
  rule      = aws_cloudwatch_event_rule.ingest_schedule.name
  target_id = "ingest-lambda"
  arn       = aws_lambda_function.ingest_lambda.arn
  input     = jsonencode({ symbol = var.ingest_symbol })
}

resource "aws_lambda_permission" "allow_eventbridge_ingest" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ingest_schedule.arn
}
