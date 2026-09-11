data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  common_tags = merge(
    var.tags,
    {
      Project   = var.project_prefix
      ManagedBy = "terraform"
    },
  )

  # Logical names — used as resource keys and embedded in IAM role names.
  # The app.py reads these names from MEMORIES / BROWSERS env vars.
  container_runtime_name = "container_agent"
  code_runtime_name      = "python_agent"
  memory_name            = "semantic_memory"
  gateway_name           = "mcp-gateway"
  gateway_target_name    = "lambda-target"
  browser_name           = "web_browser"
  code_interpreter_name  = "python_interpreter"

  ecr_image_uri = "${aws_ecr_repository.container_runtime.repository_url}:build-${local.container_build_id}"
}
