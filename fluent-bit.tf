# poc-fargate/fluent-bit.tf
# This file defines the Fluent Bit configuration for log forwarding from ECS tasks to Kinesis Firehose and CloudWatch Logs.

resource "aws_s3_object" "fluent_bit_config" {
  bucket  = aws_s3_bucket.firehose.id
  key     = "fluent-bit-config/fluent-bit.conf"
  content = <<-EOF
[SERVICE]
    Flush         5
    Log_Level     info
    Daemon        off
    Parsers_File  parsers.conf

[INPUT]
    Name              forward
    Listen            0.0.0.0
    Port              24224
    Buffer_Chunk_Size 1M
    Buffer_Max_Size   6M

[OUTPUT]
    Name            firehose
    Match           app.*
    region          ${local.region}
    delivery_stream ${aws_kinesis_firehose_delivery_stream.firehose_stream.name}
    log_retention_days 30

[OUTPUT]
    Name            cloudwatch_logs
    Match           app.*
    region          ${local.region}
    log_group_name  /aws/ecs/poc-ecs-service/poc-ecs-app
    log_stream_name from-fluent-bit
    auto_create_group true
EOF
}

resource "aws_s3_object" "fluent_bit_parsers" {
  bucket  = aws_s3_bucket.firehose.id
  key     = "fluent-bit-config/parsers.conf"
  content = <<-EOF
[PARSER]
    Name   json
    Format json
    Time_Key time
    Time_Format %d/%b/%Y:%H:%M:%S %z
    Time_Keep On

[PARSER]
    Name   docker
    Format json
    Time_Key time
    Time_Format %Y-%m-%dT%H:%M:%S.%L%z
    Time_Keep On

[PARSER]
    Name   syslog
    Format regex
    Regex  ^\<(?<pri>[0-9]+)\>(?<time>[^ ]* [^ ]* [^ ]*) (?<host>[^ ]*) (?<ident>[a-zA-Z0-9_\/\.\-]*)(?:\[(?<pid>[0-9]+)\])?(?:[^\:]*\:)? *(?<message>.*)$
    Time_Key time
    Time_Format %b %d %H:%M:%S
EOF
}
