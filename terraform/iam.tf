# ── IAM 역할/정책 ─────────────────────────────────────────────────────────────
# 최소 권한 원칙: API는 SQS 전송만, Worker는 SQS 수신·삭제 + S3 적재만 허용한다.
# 실행 역할(execution role)과 태스크 역할(task role)을 분리한다:
#   - 실행 역할: ECS 에이전트가 이미지 pull, 로그 전송 등에 사용(인프라용)
#   - 태스크 역할: 컨테이너 안 애플리케이션 코드가 AWS API 호출에 사용(앱용)

# ECS 태스크가 역할을 위임받기 위한 신뢰 정책(누가 이 역할을 assume 할 수 있는지).
data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# ── 실행 역할(execution role) ──
# 이미지 pull(ECR) + 컨테이너 로그 전송(CloudWatch)에 필요한 표준 권한.
resource "aws_iam_role" "ecs_task_execution" {
  name               = "${var.project_name}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = local.common_tags
}

# AWS 관리형 정책(ECR pull + Logs 전송)을 그대로 부착.
resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ── 태스크 역할(task role): API / Worker 각각 분리 ──
resource "aws_iam_role" "api_task" {
  name               = "${var.project_name}-api-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role" "worker_task" {
  name               = "${var.project_name}-worker-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = local.common_tags
}

# API 권한: 로그 큐로 메시지 전송만 허용(수신·삭제 권한 없음).
resource "aws_iam_role_policy" "api_sqs" {
  name = "${var.project_name}-api-sqs-policy"
  role = aws_iam_role.api_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.logs.arn # 특정 큐로만 한정
      }
    ]
  })
}

# Worker 권한: 큐에서 수신·삭제 + S3 raw 경로에 적재.
# S3는 버킷 전체가 아니라 raw/ 접두사 아래로만 PutObject 허용(범위 최소화).
resource "aws_iam_role_policy" "worker_sqs_s3" {
  name = "${var.project_name}-worker-sqs-s3-policy"
  role = aws_iam_role.worker_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.logs.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:AbortMultipartUpload"
        ]
        Resource = "${aws_s3_bucket.raw_logs.arn}/raw/*"
      }
    ]
  })
}
