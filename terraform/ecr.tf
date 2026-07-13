# ── ECR: 컨테이너 이미지 저장소 ───────────────────────────────────────────────
# CI/CD가 빌드한 api/worker 이미지를 푸시하고, ECS 태스크가 여기서 pull 한다.

resource "aws_ecr_repository" "api" {
  name                 = "${var.project_name}-api"
  image_tag_mutability = "MUTABLE" # 같은 태그(latest 등) 재푸시 허용

  # 푸시 시 자동으로 이미지 취약점 스캔 수행.
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.common_tags
}

resource "aws_ecr_repository" "worker" {
  name                 = "${var.project_name}-worker"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.common_tags
}
