# ===== lambda.tf =====
# Lambda function
resource "aws_lambda_function" "guestbook" {
  function_name = "${var.project_name}-${var.environment}"
  role          = aws_iam_role.lambda_role.arn

  package_type = "Image"
  image_uri    = local.image_uri

  memory_size = var.lambda_memory_size
  timeout     = var.lambda_timeout

  architectures = ["arm64"]

  environment {
    variables = {
      DDB_TABLE    = aws_dynamodb_table.guestbook.name
      ENVIRONMENT  = var.environment
      NODE_NAME    = "serverless"
      AWS_LWA_PORT = "8080"

      # This allows us to use an arbitrary APIGW route
      BASE_PATH = local.base_path
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_dynamodb
  ]

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-lambda"
    }
  )
}

# Lambda resource policy to allow API Gateway
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.guestbook.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.guestbook.execution_arn}/*/*"
}