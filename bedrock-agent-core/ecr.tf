# Private image storage for the CONTAINER runtime; container_build.tf pushes here.
resource "aws_ecr_repository" "container_runtime" {
  # Group the runtime repository under the project's namespace.
  name = "${var.project_prefix}/${local.container_runtime_name}"

  # Prevent overwriting build-<build ID> tags. The build script reuses an existing
  # tag so retries keep the published image associated with that build ID.
  image_tag_mutability = "IMMUTABLE"

  # Let Terraform delete the repository and its images during demo teardown,
  force_delete = true

  image_scanning_configuration {
    # Request vulnerability scans after pushes so findings are available to review.
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  # Apply user-supplied tags plus the shared Project and ManagedBy labels.
  tags = local.common_tags
}

# Bound image storage growth while keeping a small history of recent builds.
resource "aws_ecr_lifecycle_policy" "container_runtime" {

  repository = aws_ecr_repository.container_runtime.name

  # ECR accepts a JSON policy; encode the Terraform object into that format.
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description = "Keep last 10 images"
      # Keep the ten most recently pushed images for a limited build history.
      selection = {
        tagStatus = "any"
        countType = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        # Delete selected images asynchronously through ECR's lifecycle service.
        type = "expire"
      }
    }]
  })
}
