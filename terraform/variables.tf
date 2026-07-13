variable "aws_region" {
  description = "AWS region to deploy the reference architecture."
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "Resource name prefix."
  type        = string
  default     = "supercent-log-pipeline"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "container_port" {
  description = "API container port."
  type        = number
  default     = 3000
}

variable "api_desired_count" {
  description = "Desired number of API tasks."
  type        = number
  default     = 2
}

variable "worker_desired_count" {
  description = "Desired number of worker tasks."
  type        = number
  default     = 2
}


variable "image_tag" {
  description = "Container image tag pushed by CI/CD."
  type        = string
  default     = "latest"
}
