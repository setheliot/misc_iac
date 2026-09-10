# ─── CODE runtime ───
# https://registry.terraform.io/providers/hashicorp/awscc/latest/docs/data-sources/bedrockagentcore_runtime

resource "awscc_bedrockagentcore_runtime" "code_agent" {
  agent_runtime_name = local.code_runtime_name
  description        = "Python-based agent runtime"
  role_arn           = aws_iam_role.runtime.arn

  agent_runtime_artifact = {
    code_configuration = {
      code = {
        s3 = {
          bucket = aws_s3_bucket.code_runtime.id
          prefix = aws_s3_object.code_runtime_source.key
        }
      }
      entry_point = ["agent.py"]
      runtime     = "PYTHON_3_11"
    }
  }

  network_configuration = {
    network_mode = "PUBLIC"
  }

  environment_variables = {
    LOG_LEVEL = var.code_agent_log_level
  }

  tags = local.common_tags

  depends_on = [
    time_sleep.runtime_iam_propagation,
    aws_s3_object.code_runtime_source,
  ]
}

# ─── CONTAINER runtime ───
resource "awscc_bedrockagentcore_runtime" "container_agent" {
  agent_runtime_name = local.container_runtime_name
  description        = "Container-based agent runtime with STRANDS"
  role_arn           = aws_iam_role.runtime.arn

  agent_runtime_artifact = {
    container_configuration = {
      container_uri = local.ecr_image_uri
    }
  }

  network_configuration = {
    network_mode = "PUBLIC"
  }

  # MEMORIES / BROWSERS env vars expose AgentCore resource ARNs to the agent
  # code under stable logical names — app.py looks up memories["semantic_memory"]
  # and browsers["web_browser"]. AWS-assigned IDs carry a per-deploy suffix
  # the logical keys do not.
  environment_variables = {
    MODEL_ID = var.bedrock_model_id
    MEMORIES = jsonencode({
      (local.memory_name) = {
        arn = awscc_bedrockagentcore_memory.semantic_memory.memory_arn
      }
    })
    BROWSERS = jsonencode({
      (local.browser_name) = {
        arn = awscc_bedrockagentcore_browser_custom.web_browser.browser_arn
      }
    })
  }

  tags = local.common_tags

  depends_on = [
    null_resource.container_build_push,
    time_sleep.runtime_iam_propagation,
  ]
}

# ─── Runtime endpoints ───
# agent_runtime_version is pinned so the endpoint follows version bumps; without
# it the endpoint sticks at the version that existed at create time and never
# picks up new images or env-var changes.

resource "awscc_bedrockagentcore_runtime_endpoint" "code_agent" {
  name                  = "${local.code_runtime_name}_endpoint"
  agent_runtime_id      = awscc_bedrockagentcore_runtime.code_agent.agent_runtime_id
  agent_runtime_version = awscc_bedrockagentcore_runtime.code_agent.agent_runtime_version
  tags                  = local.common_tags
}

resource "awscc_bedrockagentcore_runtime_endpoint" "container_agent" {
  name                  = "${local.container_runtime_name}_endpoint"
  agent_runtime_id      = awscc_bedrockagentcore_runtime.container_agent.agent_runtime_id
  agent_runtime_version = awscc_bedrockagentcore_runtime.container_agent.agent_runtime_version
  tags                  = local.common_tags
}
