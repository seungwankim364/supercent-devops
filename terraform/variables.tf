# 스택 전반에서 사용하는 입력 변수 정의. 값은 여기 default를 쓰거나 tfvars/CLI로 덮어쓴다.

variable "aws_region" {
  description = "AWS region to deploy the reference architecture." # 배포 리전
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "Resource name prefix." # 모든 리소스 이름 앞에 붙는 접두사
  type        = string
  default     = "supercent-log-pipeline"
}

variable "environment" {
  description = "Environment name." # 환경 구분(dev/stage/prod 등). 태그·버킷명 등에 사용
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC." # VPC 대역. 서브넷은 이 대역을 잘라서 배정
  type        = string
  default     = "10.20.0.0/16"
}

variable "container_port" {
  description = "API container port." # API 컨테이너가 리스닝하는 포트(앱의 PORT와 일치해야 함)
  type        = number
  default     = 3000
}

variable "api_desired_count" {
  description = "Desired number of API tasks." # API 서비스 기본 태스크 수(오토스케일 최소치와 맞춤)
  type        = number
  default     = 2
}

variable "worker_desired_count" {
  description = "Desired number of worker tasks." # Worker 서비스 기본 태스크 수
  type        = number
  default     = 2
}

variable "image_tag" {
  description = "Container image tag pushed by CI/CD." # CI/CD가 ECR에 푸시한 이미지 태그
  type        = string
  default     = "latest"
}
