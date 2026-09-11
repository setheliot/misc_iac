# https://registry.terraform.io/providers/hashicorp/awscc/latest/docs/data-sources/bedrockagentcore_gateway

resource "awscc_bedrockagentcore_gateway" "mcp_gateway" {
  name            = local.gateway_name
  description     = "Gateway for Model Context Protocol connections"
  role_arn        = aws_iam_role.gateway.arn
  authorizer_type = "AWS_IAM"
  protocol_type   = "MCP"

  protocol_configuration = {
    mcp = {
      instructions       = "Gateway for external service integration"
      search_type        = "SEMANTIC"
      supported_versions = ["2025-11-25"]
    }
  }

  tags = local.common_tags
}

resource "aws_bedrockagentcore_gateway_target" "lambda_target" {
  name               = "${var.project_prefix}-${local.gateway_target_name}"
  gateway_identifier = awscc_bedrockagentcore_gateway.mcp_gateway.gateway_identifier
  description        = "Lambda function integration"

  depends_on = [
    awscc_bedrockagentcore_gateway.mcp_gateway,
    aws_iam_role_policy.gateway,
    time_sleep.gateway_iam_propagation,
  ]

  credential_provider_configuration {
    gateway_iam_role {}
  }

  target_configuration {
    mcp {
      lambda {
        lambda_arn = aws_lambda_function.gateway_target.arn

        tool_schema {
          inline_payload {
            name        = "process_request"
            description = "Process requests via Lambda"

            input_schema {
              type        = "object"
              description = "Request input"

              property {
                name        = "query"
                type        = "string"
                description = "Query to process"
                required    = true
              }
            }

            output_schema {
              type = "object"

              property {
                name     = "result"
                type     = "string"
                required = true
              }
            }
          }
        }
      }
    }
  }
}
