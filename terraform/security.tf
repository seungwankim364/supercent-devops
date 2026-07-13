# ── 보안 그룹(방화벽) ─────────────────────────────────────────────────────────
# 3계층으로 트래픽을 최소 권한 원칙에 맞게 제한한다:
#   인터넷 → ALB → ECS 태스크 → (VPC 엔드포인트 / S3)
# 각 계층은 바로 앞 계층에서 오는 트래픽만 허용한다.

# ALB용 SG: 인터넷에서 오는 HTTP(80)만 허용하고, ECS 태스크로만 나간다.
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow public HTTP traffic to the API ALB"
  vpc_id      = aws_vpc.main.id

  # 인바운드: 인터넷 어디서든 80 포트 허용(공개 로그 수집 엔드포인트).
  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 아웃바운드: VPC 내부의 API 컨테이너 포트로만 전달.
  egress {
    description = "Forward traffic to ECS API tasks"
    from_port   = var.container_port
    to_port     = var.container_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-alb-sg"
  })
}

# ECS 태스크용 SG: 인바운드는 ALB에서 오는 것만, 아웃바운드는 443(VPC 엔드포인트 + S3)만.
# → 태스크가 임의의 인터넷 목적지로 나가지 못하게 묶는다.
resource "aws_security_group" "ecs" {
  name        = "${var.project_name}-ecs-sg"
  description = "Allow ALB to reach API tasks and outbound AWS service access"
  vpc_id      = aws_vpc.main.id

  # 인바운드: ALB SG에서 오는 API 트래픽만 허용(CIDR가 아니라 SG로 지정 → 더 좁고 안전).
  ingress {
    description     = "API traffic from ALB only"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # 아웃바운드 1: 인터페이스 VPC 엔드포인트(ECR/Logs/SQS)로 향하는 HTTPS.
  egress {
    description = "Outbound HTTPS to interface VPC endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"

    security_groups = [
      aws_security_group.vpc_endpoint.id
    ]
  }

  # 아웃바운드 2: S3 게이트웨이 엔드포인트로 향하는 HTTPS(prefix list로 S3 대역만 허용).
  egress {
    description     = "HTTPS to S3 gateway endpoint"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [data.aws_prefix_list.s3.id]
  }


  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ecs-sg"
  })
}

# S3 게이트웨이 엔드포인트의 prefix list ID 조회(위 egress 규칙에서 목적지로 사용).
data "aws_prefix_list" "s3" {
  name = "com.amazonaws.${var.aws_region}.s3"
}

# 인터페이스 VPC 엔드포인트용 SG: ECS 태스크에서 오는 HTTPS(443)만 받아들인다.
resource "aws_security_group" "vpc_endpoint" {
  name        = "${var.project_name}-vpc-endpoint-sg"
  description = "Allow HTTPS from ECS to VPC endpoints"
  vpc_id      = aws_vpc.main.id

  # 인바운드: ECS SG에서 오는 443만 허용.
  ingress {
    description = "HTTPS from ECS tasks"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    security_groups = [
      aws_security_group.ecs.id
    ]
  }

  egress {
    description = "Outbound HTTPS to AWS service VPC endpoints"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpc-endpoints-sg"
  })
}
