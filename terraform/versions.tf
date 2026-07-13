# Terraform / 프로바이더 버전 고정
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # AWS 프로바이더 5.x 계열 사용
    }
  }
}

# 배포 대상 리전
provider "aws" {
  region = var.aws_region
}
