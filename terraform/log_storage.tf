data "aws_caller_identity" "current" {}

resource "aws_sqs_queue" "logs" {
  name                       = "${var.project_name}-logs"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 345600

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.logs_dlq.arn
    maxReceiveCount     = 5
  })

  tags = local.common_tags
}

resource "aws_sqs_queue" "logs_dlq" {
  name                      = "${var.project_name}-logs-dlq"
  message_retention_seconds = 1209600

  tags = local.common_tags
}

resource "aws_s3_bucket" "raw_logs" {
  bucket = "${var.project_name}-${var.environment}-raw-logs-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-raw-logs"
  })
}

resource "aws_s3_bucket_public_access_block" "raw_logs" {
  bucket                  = aws_s3_bucket.raw_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_glue_catalog_database" "logs" {
  name = replace("${var.project_name}_${var.environment}", "-", "_")
}

resource "aws_glue_catalog_table" "raw_logs" {
  name          = "raw_game_logs"
  database_name = aws_glue_catalog_database.logs.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    classification = "json"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.raw_logs.bucket}/raw/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "json-serde"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "messageId"
      type = "string"
    }

    columns {
      name = "receivedAt"
      type = "string"
    }

    columns {
      name = "payload"
      type = "string"
    }

    columns {
      name = "storedAt"
      type = "string"
    }
  }
}

resource "aws_athena_workgroup" "logs" {
  name = "${var.project_name}-${var.environment}"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.raw_logs.bucket}/athena-results/"
    }
  }

  tags = local.common_tags
}
