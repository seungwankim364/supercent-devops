# ── 출력값 ────────────────────────────────────────────────────────────────────
# apply 후 확인/연동에 필요한 핵심 값들. (예: 로그 전송 대상, 이미지 푸시 대상, 조회 워크그룹)

output "alb_dns_name" {
  description = "Public ALB DNS name for the log API." # 로그 전송 엔드포인트 주소
  value       = aws_lb.api.dns_name
}

output "api_ecr_repository_url" {
  description = "ECR repository URL for the API image." # CI/CD가 API 이미지를 푸시할 곳
  value       = aws_ecr_repository.api.repository_url
}

output "worker_ecr_repository_url" {
  description = "ECR repository URL for the worker image." # Worker 이미지 푸시 대상
  value       = aws_ecr_repository.worker.repository_url
}

output "sqs_queue_url" {
  description = "SQS queue URL for log ingestion." # 앱이 사용하는 큐 URL
  value       = aws_sqs_queue.logs.url
}

output "raw_log_bucket" {
  description = "S3 bucket for raw game logs." # raw 로그 적재 버킷
  value       = aws_s3_bucket.raw_logs.bucket
}

output "athena_workgroup" {
  description = "Athena workgroup for querying raw logs." # 로그 SQL 조회용 워크그룹
  value       = aws_athena_workgroup.logs.name
}
