# 현재 리전에서 사용 가능한 가용영역(AZ) 목록을 조회한다.
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # 고가용성을 위해 앞의 2개 AZ만 사용한다(서브넷/NAT를 AZ별로 이중화).
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # 모든 리소스에 공통으로 붙이는 태그. 비용 추적·소유 구분·관리 주체 식별에 사용.
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
