# Terraform / 프로바이더 버전 고정.
# 팀원·CI 어디서 실행해도 동일한 버전으로 동작하도록 최소 버전을 명시한다.
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # AWS 프로바이더 5.x 계열 사용
    }
  }
}

# 배포 대상 리전(기본 ap-northeast-2, variables.tf에서 조정 가능).
provider "aws" {
  region = var.aws_region
}
