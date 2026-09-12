# This builds the CONTAINER agent, which is only one of the agents in this repo

# Local ARM64 build + push. A build ID names the artifact and triggers deployment.
locals {
  container_src_dir      = "${path.module}/runtime-sources/container-agent"
  container_build_script = "${path.module}/scripts/build-container.sh"

  # Keep these inputs aligned with the Dockerfile COPY instructions.
  container_src_files = sort(["Dockerfile", "app.py", "requirements.txt"])
  # Include filenames, source hashes, and build_script_hash to detect build input changes.
  container_build_id = sha256(jsonencode({
    sources           = { for f in local.container_src_files : f => filesha256("${local.container_src_dir}/${f}") }
    build_script_hash = filesha256(local.container_build_script)
  }))
}

# Rerun the build script when sources, the script, or the ECR repository URL change.
# The script reuses a matching image tag in that repository, or builds and pushes it.
resource "null_resource" "container_build_push" {
  triggers = {
    build_id     = local.container_build_id
    ecr_repo_url = aws_ecr_repository.container_runtime.repository_url
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "bash \"$BUILD_SCRIPT\""
    environment = {
      BUILD_SCRIPT         = abspath(local.container_build_script)
      BUILD_SOURCE_DIR     = abspath(local.container_src_dir)
      BUILD_REPOSITORY_URL = aws_ecr_repository.container_runtime.repository_url
      BUILD_IMAGE_TAG      = "build-${local.container_build_id}"
      BUILD_AWS_REGION     = local.region
    }
  }
}
