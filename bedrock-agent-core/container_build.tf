# Local docker build + push to ECR. Replaces the module's CodeBuild flow.
# Requires Docker + buildx + AWS CLI on the workstation running terraform apply.
#
# Re-runs on:
#   - a change to one of the container build inputs below
#   - ECR repo replacement
#   - tag change
#
# Uses buildx with --platform linux/arm64 so the image is correct regardless of
# the host architecture (AgentCore runtimes run on Graviton).

locals {
  container_src_dir = "${path.module}/runtime-sources/container-agent"

  # Keep this list aligned with the Dockerfile and its COPY inputs. Generated
  # files and documentation in the source directory do not affect the image.
  container_src_files = sort(["Dockerfile", "app.py", "requirements.txt"])
  container_src_hash = sha256(join("", [
    for f in local.container_src_files :
    filesha256("${local.container_src_dir}/${f}")
  ]))
}

resource "null_resource" "container_build_push" {
  triggers = {
    src_hash     = local.container_src_hash
    ecr_repo_url = aws_ecr_repository.container_runtime.repository_url
    image_tag    = var.container_image_tag
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      REPO_URL='${aws_ecr_repository.container_runtime.repository_url}'
      TAG='${var.container_image_tag}'
      REGION='${local.region}'
      REGISTRY='${local.account_id}.dkr.ecr.${local.region}.amazonaws.com'
      SRC_DIR='${local.container_src_dir}'

      echo "Logging in to ECR..."
      aws ecr get-login-password --region "$REGION" \
        | docker login --username AWS --password-stdin "$REGISTRY"

      echo "Building image $REPO_URL:$TAG for linux/arm64..."
      docker buildx build \
        --platform linux/arm64 \
        --provenance=false \
        --tag "$REPO_URL:$TAG" \
        --push \
        "$SRC_DIR"

      echo "Waiting for ECR eventual consistency..."
      for i in {1..30}; do
        if aws ecr describe-images \
             --repository-name '${aws_ecr_repository.container_runtime.name}' \
             --image-ids imageTag="$TAG" \
             --region "$REGION" >/dev/null 2>&1; then
          echo "Image confirmed in ECR after $i attempt(s)"
          exit 0
        fi
        sleep 2
      done
      echo "ERROR: Image not visible in ECR after 60s"
      exit 1
    EOT
  }
}
