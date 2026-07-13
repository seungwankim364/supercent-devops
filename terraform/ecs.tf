# ── ECS(Fargate) + ALB + CloudWatch Logs ─────────────────────────────────────
# 퍼블릭 ALB가 트래픽을 받아 Private 서브넷의 API 태스크로 분산하고,
# Worker 태스크는 ALB 없이 백그라운드에서 SQS를 소비한다.

# 컨테이너 로그 그룹(API/Worker). 14일 후 자동 만료.
resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/${var.project_name}/api"
  retention_in_days = 14

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "worker" {
  name              = "/ecs/${var.project_name}/worker"
  retention_in_days = 14

  tags = local.common_tags
}

# ECS 클러스터: 태스크가 실행되는 논리적 그룹.
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  tags = local.common_tags
}

# ── ALB ──
# 인터넷에 공개된 Application Load Balancer. Public 서브넷 2곳(AZ 이중화)에 배치.
resource "aws_lb" "api" {
  name               = substr("${var.project_name}-alb", 0, 32) # ALB 이름은 최대 32자
  load_balancer_type = "application"
  internal           = false # 퍼블릭
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public.id, aws_subnet.public2.id]

  tags = local.common_tags
}

# 타깃 그룹: ALB가 트래픽을 보낼 대상. Fargate는 IP 기반(target_type=ip).
# /healthz가 200을 반환하면 healthy로 판정(연속 2회 성공 시 투입, 3회 실패 시 제외).
resource "aws_lb_target_group" "api" {
  name        = substr("${var.project_name}-api-tg", 0, 32)
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    path                = "/healthz"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = local.common_tags
}

# 리스너: ALB의 80 포트로 들어온 요청을 위 타깃 그룹으로 포워딩.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.api.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

# ── API 태스크 정의 ──
# Fargate에서 실행되는 API 컨테이너의 청사진(이미지/CPU/메모리/환경변수/로그).
resource "aws_ecs_task_definition" "api" {
  family                   = "${var.project_name}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc" # Fargate 필수. 태스크마다 ENI/사설 IP 부여
  cpu                      = 512      # 0.5 vCPU
  memory                   = 1024     # 1 GB
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn # 이미지 pull/로그 전송용
  task_role_arn            = aws_iam_role.api_task.arn           # 앱의 SQS 전송 권한

  container_definitions = jsonencode([
    {
      name      = "api"
      image     = "${aws_ecr_repository.api.repository_url}:${var.image_tag}"
      essential = true
      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ]
      # 앱 코드가 읽는 환경변수. 로컬 docker-compose와 동일한 키를 사용.
      # (SQS_ENDPOINT는 주입하지 않음 → SDK가 실제 AWS SQS 엔드포인트로 연결)
      environment = [
        { name = "PORT", value = tostring(var.container_port) },
        { name = "AWS_DEFAULT_REGION", value = var.aws_region },
        { name = "SQS_QUEUE_URL", value = aws_sqs_queue.logs.url }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.api.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "api"
        }
      }
    }
  ])

  tags = local.common_tags
}

# ── Worker 태스크 정의 ──
# 포트 매핑 없음(외부 노출 X). SQS를 소비해 S3로 적재하므로 큐 URL + S3 버킷 정보를 주입.
resource "aws_ecs_task_definition" "worker" {
  family                   = "${var.project_name}-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.worker_task.arn # SQS 수신·삭제 + S3 적재 권한

  container_definitions = jsonencode([
    {
      name      = "worker"
      image     = "${aws_ecr_repository.worker.repository_url}:${var.image_tag}"
      essential = true
      environment = [
        { name = "AWS_DEFAULT_REGION", value = var.aws_region },
        { name = "SQS_QUEUE_URL", value = aws_sqs_queue.logs.url },
        { name = "RAW_LOG_BUCKET", value = aws_s3_bucket.raw_logs.bucket },
        { name = "RAW_LOG_PREFIX", value = "raw/" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.worker.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "worker"
        }
      }
    }
  ])

  tags = local.common_tags
}

# ── API 서비스 ──
# 태스크를 원하는 개수만큼 유지하고 ALB에 등록한다. Private 서브넷 배치(공인 IP 없음).
resource "aws_ecs_service" "api" {
  name            = "${var.project_name}-api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.api_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private.id, aws_subnet.private2.id]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false # 아웃바운드는 NAT/VPC 엔드포인트를 통해서만
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = var.container_port
  }

  depends_on = [aws_lb_listener.http] # 리스너가 준비된 뒤 서비스 등록

  tags = local.common_tags
}

# ── Worker 서비스 ──
# ALB에 붙지 않고 큐만 소비. 그 외 구성은 API 서비스와 동일.
resource "aws_ecs_service" "worker" {
  name            = "${var.project_name}-worker"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = var.worker_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private.id, aws_subnet.private2.id]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  tags = local.common_tags
}
