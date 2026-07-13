# ── 로그 적재 파이프라인(관리형) ──────────────────────────────────────────────
# SQS(+DLQ) → S3(raw 로그) → Glue Data Catalog → Athena(SQL 조회).
# 로컬의 SQS+DLQ redrive 구조(scripts/init-sqs.sh)를 AWS 관리형으로 그대로 옮긴 형태.

# 배포 계정 ID 조회(S3 버킷 이름을 전역 고유하게 만들기 위해 사용).
data "aws_caller_identity" "current" {}

# 메인 로그 큐. maxReceiveCount(5) 초과 시 DLQ로 자동 이동(redrive).
resource "aws_sqs_queue" "logs" {
  name                       = "${var.project_name}-logs"
  visibility_timeout_seconds = 60     # 수신 후 60초간 다른 소비자에게 안 보임
  message_retention_seconds  = 345600 # 4일 보관(큐는 임시 버퍼일 뿐, 영속 저장은 S3가 담당)

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.logs_dlq.arn
    maxReceiveCount     = 5
  })

  tags = local.common_tags
}

# DLQ. 처리에 반복 실패한 메시지를 유실 없이 격리. 조사 시간을 벌기 위해 보관 기간을 길게(14일).
resource "aws_sqs_queue" "logs_dlq" {
  name                      = "${var.project_name}-logs-dlq"
  message_retention_seconds = 1209600 # 14일(최대치)

  tags = local.common_tags
}

# raw 로그 저장 버킷. 버킷명은 전역 고유해야 하므로 계정 ID를 접미사로 붙인다.
resource "aws_s3_bucket" "raw_logs" {
  bucket = "${var.project_name}-${var.environment}-raw-logs-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-raw-logs"
  })
}

# 로그에는 민감 데이터가 있을 수 있으므로 퍼블릭 액세스를 전면 차단.
resource "aws_s3_bucket_public_access_block" "raw_logs" {
  bucket                  = aws_s3_bucket.raw_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Glue 데이터베이스. Athena가 조회할 테이블의 논리적 그룹.
# 이름에 하이픈이 안 되므로 언더스코어로 치환.
resource "aws_glue_catalog_database" "logs" {
  name = replace("${var.project_name}_${var.environment}", "-", "_")
}

# Glue 테이블: S3의 raw/ 경로에 쌓인 JSON 로그를 SQL로 조회할 수 있게 스키마를 정의.
# JSON SerDe로 각 줄(JSON)을 파싱한다. (payload는 중첩 객체지만 여기서는 string으로 취급)
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

    # 로그 1건의 컬럼 구성(worker가 저장하는 필드와 동일).
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

# Athena 워크그룹: SQL 조회 실행 단위. 결과는 지정한 S3 경로에 저장된다.
resource "aws_athena_workgroup" "logs" {
  name = "${var.project_name}-${var.environment}"

  configuration {
    enforce_workgroup_configuration    = true # 사용자가 결과 위치 등을 못 바꾸게 워크그룹 설정 강제
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.raw_logs.bucket}/athena-results/"
    }
  }

  tags = local.common_tags
}
