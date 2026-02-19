# poc-fargate/firehose.tf

# This file defines the AWS resources needed for Kinesis Firehose to deliver logs to S3 and CloudWatch.
resource "aws_s3_bucket" "firehose" {
  bucket        = "poc-fargate-${replace(substr(data.aws_caller_identity.current.account_id, 0, 6), "/", "")}"
  force_destroy = true
}

resource "aws_iam_role" "firehose_role" {
  name = "poc-fargate-firehose-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "firehose.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "firehose_policy" {
  name = "poc-fargate-firehose-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:AbortMultipartUpload", "s3:GetBucketLocation", "s3:ListBucket"]
        Resource = [aws_s3_bucket.firehose.arn, "${aws_s3_bucket.firehose.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:log-group:/aws/kinesisfirehose/poc-fargate*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.firehose.arn}/fluent-bit-config/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "firehose_attach" {
  role       = aws_iam_role.firehose_role.name
  policy_arn = aws_iam_policy.firehose_policy.arn
}

resource "aws_cloudwatch_log_group" "firehose" {
  name              = "/aws/kinesisfirehose/poc-fargate"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_stream" "firehose_stream" {
  name           = "delivery-errors"
  log_group_name = aws_cloudwatch_log_group.firehose.name
}

resource "aws_kinesis_firehose_delivery_stream" "firehose_stream" {
  name        = "poc-fargate-firehose-stream"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn           = aws_iam_role.firehose_role.arn
    bucket_arn         = aws_s3_bucket.firehose.arn
    compression_format = "GZIP"
    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = aws_cloudwatch_log_stream.firehose_stream.name
    }
  }

  # depends_on = [aws_cloudwatch_log_group.firehose]
}
