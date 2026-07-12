output "alb_dns_name" {
  description = "Public ALB DNS name for the log API."
  value       = aws_lb.api.dns_name
}

output "api_ecr_repository_url" {
  description = "ECR repository URL for the API image."
  value       = aws_ecr_repository.api.repository_url
}

output "worker_ecr_repository_url" {
  description = "ECR repository URL for the worker image."
  value       = aws_ecr_repository.worker.repository_url
}

output "sqs_queue_url" {
  description = "SQS queue URL for log ingestion."
  value       = aws_sqs_queue.logs.url
}

output "raw_log_bucket" {
  description = "S3 bucket for raw game logs."
  value       = aws_s3_bucket.raw_logs.bucket
}

output "athena_workgroup" {
  description = "Athena workgroup for querying raw logs."
  value       = aws_athena_workgroup.logs.name
}
