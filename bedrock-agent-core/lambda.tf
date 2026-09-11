data "archive_file" "gateway_target_lambda" {
  type        = "zip"
  output_path = "${path.module}/.terraform/tmp/gateway-target-lambda.zip"

  source {
    content  = <<-EOT
      exports.handler = async (event) => {
        return {
          statusCode: 200,
          body: JSON.stringify({ message: "Hello from gateway target!" })
        };
      };
    EOT
    filename = "index.js"
  }
}

resource "aws_lambda_function" "gateway_target" {
  filename         = data.archive_file.gateway_target_lambda.output_path
  function_name    = "${var.project_prefix}-gateway-target"
  role             = aws_iam_role.lambda.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  source_code_hash = data.archive_file.gateway_target_lambda.output_base64sha256

  tracing_config {
    mode = "Active"
  }

  tags = local.common_tags
}
