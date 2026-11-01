# poc-fargate/deploy-gates.tf

# Deterministic gates of the nginx blue/green deployment:
# 1. POST_TEST_TRAFFIC_SHIFT hook: a Lambda calls the new revision through the
#    test listener rule; FAILED = ECS rolls back before any user sees it.
# 2. Deployment alarm: target 5xx on the ALB during the bake time; ALARM =
#    ECS shifts production traffic back to the previous revision.

locals {
  smoke_test_name = "${local.name}-bg-smoke-test"
}

data "archive_file" "smoke_test" {
  count       = var.enable_alb ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/lambda/smoke_test/index.py"
  output_path = "${path.module}/.terraform/tmp/smoke_test.zip"
}

resource "aws_cloudwatch_log_group" "smoke_test" {
  count             = var.enable_alb ? 1 : 0
  name              = "/aws/lambda/${local.smoke_test_name}"
  retention_in_days = var.log_retention
  tags              = local.tags
}

resource "aws_iam_role" "smoke_test" {
  count = var.enable_alb ? 1 : 0
  name  = local.smoke_test_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

# The function only writes its own log group; it reaches the service over
# public HTTPS like a user would, so it needs no AWS API access at all.
resource "aws_iam_role_policy" "smoke_test_logs" {
  count = var.enable_alb ? 1 : 0
  name  = "logs"
  role  = aws_iam_role.smoke_test[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.smoke_test[0].arn}:*"
    }]
  })
}

resource "aws_lambda_function" "smoke_test" {
  count            = var.enable_alb ? 1 : 0
  function_name    = local.smoke_test_name
  description      = "ECS blue/green POST_TEST_TRAFFIC_SHIFT hook for ${local.fqdn}"
  role             = aws_iam_role.smoke_test[0].arn
  runtime          = "python3.13"
  handler          = "index.handler"
  filename         = data.archive_file.smoke_test[0].output_path
  source_code_hash = data.archive_file.smoke_test[0].output_base64sha256
  timeout          = 60
  memory_size      = 128

  environment {
    variables = {
      TARGET_URL        = "https://${local.fqdn}${var.smoke_test_path}"
      TEST_HEADER       = "X-Blue-Green"
      TEST_HEADER_VALUE = "test"
    }
  }

  depends_on = [aws_cloudwatch_log_group.smoke_test]
  tags       = local.tags
}

# Role ECS assumes to invoke the hook: this one function and nothing else
# (the module's infrastructure role is for the load balancer only).
resource "aws_iam_role" "deploy_hook" {
  count = var.enable_alb ? 1 : 0
  name  = "${local.name}-ecs-deploy-hook"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
      }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "deploy_hook_invoke" {
  count = var.enable_alb ? 1 : 0
  name  = "invoke-smoke-test"
  role  = aws_iam_role.deploy_hook[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = aws_lambda_function.smoke_test[0].arn
    }]
  })
}

resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  count               = var.enable_alb ? 1 : 0
  alarm_name          = "${local.name}-target-5xx"
  alarm_description   = "nginx returns 5xx: rolls back an in-progress blue/green deployment"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = { LoadBalancer = module.alb[0].arn_suffix }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = var.alarm_5xx_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  tags                = local.tags
}
