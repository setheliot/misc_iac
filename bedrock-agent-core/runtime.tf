# Deployment flow: versioned artifacts -> runtimes -> stable named endpoints.
# Both runtimes use the execution role in iam.tf for AWS access from agent code.

# CODE runtime: launch a Python entry point from the ZIP uploaded by code_build.tf.
resource "awscc_bedrockagentcore_runtime" "code_agent" {
  agent_runtime_name = local.code_runtime_name
  description        = "Python-based agent runtime"
  role_arn           = aws_iam_role.runtime.arn

  agent_runtime_artifact = {
    code_configuration = {
      code = {
        s3 = {
          bucket = aws_s3_bucket.code_runtime.id
          # The API calls this "prefix", but it is the complete ZIP object key.
          prefix = aws_s3_object.code_runtime_source.key
          # A new ZIP version updates the runtime even though its key is unchanged.
          version_id = aws_s3_object.code_runtime_source.version_id
        }
      }
      # Match the filename inside the ZIP and the Python version used for packaging.
      entry_point = ["agent.py"]
      runtime     = "PYTHON_3_11"
    }
  }

  # Use AgentCore-managed public networking without attaching a customer VPC.
  network_configuration = {
    network_mode = "PUBLIC"
  }

  environment_variables = {
    LOG_LEVEL = var.code_agent_log_level
  }

  tags = local.common_tags

  # Wait for the uploaded artifact and IAM propagation before runtime creation.
  depends_on = [
    time_sleep.runtime_iam_propagation,
    aws_s3_object.code_runtime_source,
  ]
}

# CONTAINER runtime: run the Strands app from the image pushed by container_build.tf.
resource "awscc_bedrockagentcore_runtime" "container_agent" {
  agent_runtime_name = local.container_runtime_name
  description        = "Container-based agent runtime with STRANDS"
  role_arn           = aws_iam_role.runtime.arn

  agent_runtime_artifact = {
    container_configuration = {
      # The image tag contains the build ID, so source edits update the runtime.
      container_uri = local.ecr_image_uri
    }
  }

  # The weather tool calls public APIs over this runtime's internet connection.
  network_configuration = {
    network_mode = "PUBLIC"
  }

  # Environment values are strings, so encode resource maps as JSON for app.py.
  # Logical keys match its lookups; AWS-assigned ARNs can change on recreation.
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

  # The image URI alone does not tell Terraform to wait for the local Docker push.
  depends_on = [
    null_resource.container_build_push,
    time_sleep.runtime_iam_propagation,
  ]
}

# Runtime endpoints: keep caller-facing names while advancing their runtime versions.
# AWSCC retains the resource's old version in the update plan. Read it again
# after the runtime update so the named endpoint receives the new version in
# the same apply. With no runtime changes, these reads happen during planning.
data "awscc_bedrockagentcore_runtime" "code_agent_current" {
  id = awscc_bedrockagentcore_runtime.code_agent.id

  depends_on = [awscc_bedrockagentcore_runtime.code_agent]
}

data "awscc_bedrockagentcore_runtime" "container_agent_current" {
  id = awscc_bedrockagentcore_runtime.container_agent.id

  depends_on = [awscc_bedrockagentcore_runtime.container_agent]
}

resource "awscc_bedrockagentcore_runtime_endpoint" "code_agent" {
  name                  = "${local.code_runtime_name}_endpoint"
  agent_runtime_id      = awscc_bedrockagentcore_runtime.code_agent.agent_runtime_id
  agent_runtime_version = data.awscc_bedrockagentcore_runtime.code_agent_current.agent_runtime_version
  tags                  = local.common_tags
}

resource "awscc_bedrockagentcore_runtime_endpoint" "container_agent" {
  name                  = "${local.container_runtime_name}_endpoint"
  agent_runtime_id      = awscc_bedrockagentcore_runtime.container_agent.agent_runtime_id
  agent_runtime_version = data.awscc_bedrockagentcore_runtime.container_agent_current.agent_runtime_version
  tags                  = local.common_tags
}
