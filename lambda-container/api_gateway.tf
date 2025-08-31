# ===== api_gateway.tf =====
# HTTP API Gateway
resource "aws_apigatewayv2_api" "guestbook" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins     = ["*"]
    allow_methods     = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers     = ["content-type", "x-amz-date", "authorization", "x-api-key", "x-amz-security-token"]
    expose_headers    = ["x-request-id"]
    max_age           = 300
    allow_credentials = false
  }

  tags = local.common_tags
}

# API Gateway Integration with Lambda
# Creates integration_uri of the form
# "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:253490795979:function:guestbook-app-demo/invocations"
#      arn:aws:apigateway:<region>:lambda:path/2015-03-31 → fixed prefix for Lambda integrations
#      /functions/<lambda-function-arn>/invocations → tells API Gateway which function to invoke
resource "aws_apigatewayv2_integration" "lambda" {
  api_id           = aws_apigatewayv2_api.guestbook.id
  integration_type = "AWS_PROXY"

  integration_method     = "POST"
  integration_uri        = aws_lambda_function.guestbook.invoke_arn
  payload_format_version = "2.0"
}

# API Gateway Routes - Configure based on your app's endpoints
resource "aws_apigatewayv2_route" "get_entries" {
  api_id    = aws_apigatewayv2_api.guestbook.id
  route_key = "GET ${local.base_path}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "post_entry" {
  api_id    = aws_apigatewayv2_api.guestbook.id
  route_key = "POST ${local.base_path}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# Users are likely to hit the bare URL (no route) so help them when they do
resource "aws_apigatewayv2_route" "get_bare" {
  api_id    = aws_apigatewayv2_api.guestbook.id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# # # Catch-all route
# resource "aws_apigatewayv2_route" "default" {
#   api_id    = aws_apigatewayv2_api.guestbook.id
#   route_key = "$default"
#   target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
# }

# API Gateway Stage
resource "aws_apigatewayv2_stage" "guestbook" {
  api_id      = aws_apigatewayv2_api.guestbook.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      error          = "$context.error.message"
    })
  }

  tags = local.common_tags
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.project_name}-${var.environment}"
  retention_in_days = 7

  tags = local.common_tags
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.project_name}-${var.environment}"
  retention_in_days = 7

  tags = local.common_tags
}