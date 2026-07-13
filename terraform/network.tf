# ── 네트워크 계층 ─────────────────────────────────────────────────────────────
# VPC + 2개 AZ에 걸친 Public/Private 서브넷 + IGW + AZ별 NAT + 라우팅 + VPC 엔드포인트.
# Public: ALB/NAT 배치(인터넷 직접 노출). Private: ECS 태스크 배치(직접 노출 없음).

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true # 인터페이스 VPC 엔드포인트의 private DNS 사용에 필요
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}

# 인터넷 게이트웨이: Public 서브넷의 인터넷 경로.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-igw"
  })
}

# ── 서브넷 ──
# cidrsubnet(vpc, 8, n): /16을 /24 단위로 잘라 n번째 대역을 배정.
# Public은 1,2 / Private은 101,102 → 대역이 겹치지 않게 구분.

# Public 서브넷 (AZ #1) — ALB, NAT Gateway가 위치. 퍼블릭 IP 자동 할당.
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  availability_zone       = local.azs[0]
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-1"
  })
}

# Public 서브넷 (AZ #2) — 고가용성을 위한 두 번째 AZ.
resource "aws_subnet" "public2" {
  vpc_id                  = aws_vpc.main.id
  availability_zone       = local.azs[1]
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 2)
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public2"
  })
}

# Private 서브넷 (AZ #1) — ECS API/Worker 태스크가 위치. 인터넷에 직접 노출되지 않음.
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[0]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 101)

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-1"
  })
}

# Private 서브넷 (AZ #2).
resource "aws_subnet" "private2" {
  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[1]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 102)

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private2"
  })
}

# ── NAT Gateway (AZ별 이중화) ──
# Private 서브넷의 아웃바운드 인터넷 경로. 한 AZ의 NAT가 죽어도 다른 AZ는 영향받지 않도록
# AZ마다 하나씩 두어 고가용성을 확보한다. 각 NAT는 고정 공인 IP(EIP)가 필요.

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-nat-eip-1"
  })
}

resource "aws_eip" "nat2" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-nat-eip2"
  })
}

# NAT Gateway는 Public 서브넷에 위치해야 인터넷으로 나갈 수 있다.
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  depends_on = [aws_internet_gateway.main] # IGW가 먼저 생성되어야 함

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-nat-1"
  })
}

resource "aws_nat_gateway" "main2" {
  allocation_id = aws_eip.nat2.id
  subnet_id     = aws_subnet.public2.id

  depends_on = [aws_internet_gateway.main]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-nat2"
  })
}

# ── 라우팅 ──
# Public 라우트 테이블: 0.0.0.0/0 → IGW. (두 Public 서브넷 각각에 연결)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-rt"
  })
}

resource "aws_route_table" "public2" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public2-rt"
  })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public2" {
  subnet_id      = aws_subnet.public2.id
  route_table_id = aws_route_table.public2.id
}

# Private 라우트 테이블: 0.0.0.0/0 → 같은 AZ의 NAT.
# AZ별로 테이블을 분리해 각 Private 서브넷이 자기 AZ의 NAT로 나가도록 한다(교차 AZ 트래픽 최소화).
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-rt-1"
  })
}

resource "aws_route_table" "private2" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main2.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private2-rt"
  })
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private2" {
  subnet_id      = aws_subnet.private2.id
  route_table_id = aws_route_table.private2.id
}

# ── VPC 엔드포인트 ─────────────────────────────────────────────────────────────
# Private 서브넷의 ECS 태스크가 AWS 서비스(S3/ECR/CloudWatch Logs/SQS)에 접근할 때
# 인터넷(NAT)을 거치지 않고 AWS 내부 네트워크로 직접 통신하게 한다.
# → 보안 강화 + NAT 데이터 처리 비용 절감.

# S3: Gateway 타입 엔드포인트. 라우트 테이블에 경로가 추가되는 방식(비용 없음).
# raw 로그 적재(S3 PutObject) 트래픽이 이 경로를 탄다.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table_association.private.route_table_id,
    aws_route_table_association.private2.route_table_id
  ]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-s3-endpoint"
  })
}

# ECR(api): 이미지 메타데이터/인증 API 호출용 Interface 엔드포인트.
# private_dns_enabled=true → 표준 ECR 도메인이 VPC 내부에서 이 엔드포인트로 해석됨.
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids = [
    aws_subnet.private.id,
    aws_subnet.private2.id
  ]

  security_group_ids = [
    aws_security_group.vpc_endpoint.id
  ]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ecr-api-endpoint"
  })
}

# ECR(dkr): 실제 이미지 레이어 pull용 Interface 엔드포인트.
# (레이어 저장소는 S3라서 위 s3 게이트웨이 엔드포인트와 함께 있어야 pull이 완성됨)
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids = [
    aws_subnet.private.id,
    aws_subnet.private2.id
  ]

  security_group_ids = [
    aws_security_group.vpc_endpoint.id
  ]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ecr-dkr-endpoint"
  })
}

# CloudWatch Logs: 컨테이너 로그(awslogs 드라이버) 전송용 Interface 엔드포인트.
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids = [
    aws_subnet.private.id,
    aws_subnet.private2.id
  ]

  security_group_ids = [
    aws_security_group.vpc_endpoint.id
  ]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-logs-endpoint"
  })
}

# SQS: API의 SendMessage / Worker의 Receive·DeleteMessage 호출용 Interface 엔드포인트.
resource "aws_vpc_endpoint" "sqs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.sqs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids = [
    aws_subnet.private.id,
    aws_subnet.private2.id
  ]

  security_group_ids = [
    aws_security_group.vpc_endpoint.id
  ]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-sqs-endpoint"
  })
}
