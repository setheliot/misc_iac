# ─── Assume-role policy shared by all AgentCore service roles ───
data "aws_iam_policy_document" "agentcore_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["bedrock-agentcore.amazonaws.com"]
    }
  }
}

# =============================================================================
# RUNTIME IAM (shared role for both runtimes)
# =============================================================================
# Single role works for both runtimes because their permission needs differ
# only in the per-runtime artifact-source statements (S3 read vs ECR pull),
# both of which are scoped to specific resources below.

resource "aws_iam_role" "runtime" {
  name               = "${var.project_prefix}-runtime"
  assume_role_policy = data.aws_iam_policy_document.agentcore_assume_role.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "runtime_policy" {
  statement {
    sid       = "AllowCloudWatchLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:log-group:/aws/bedrock-agentcore/*"]
  }

  statement {
    sid       = "AllowXRayTracing"
    effect    = "Allow"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]
  }

  statement {
    sid       = "AllowCloudWatchMetrics"
    effect    = "Allow"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["AWS/Bedrock/AgentCore"]
    }
  }

  statement {
    sid       = "AllowBedrockModelInvocation"
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = ["*"]
  }

  # Bedrock may use AWS Marketplace on the runtime's first invocation of a
  # third-party serverless model. Keep these permissions scoped to the Claude
  # Sonnet 4.5 product that this deployment uses.
  statement {
    sid       = "AllowMarketplaceSubscriptionVisibility"
    effect    = "Allow"
    actions   = ["aws-marketplace:ViewSubscriptions"]
    resources = ["*"]
  }

  statement {
    sid       = "AllowClaudeSonnet45Subscription"
    effect    = "Allow"
    actions   = ["aws-marketplace:Subscribe"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws-marketplace:ProductId"
      values   = ["prod-mxcfnwvpd6kb4"]
    }
  }

  statement {
    sid    = "AllowWorkloadIdentityTokenManagement"
    effect = "Allow"
    actions = [
      "bedrock-agentcore:GetWorkloadIdentityToken",
      "bedrock-agentcore:RefreshWorkloadIdentityToken",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowMemoryEvents"
    effect = "Allow"
    actions = [
      "bedrock-agentcore:CreateEvent",
      "bedrock-agentcore:ListEvents",
      "bedrock-agentcore:GetEvent",
      "bedrock-agentcore:DeleteEvent",
      "bedrock-agentcore:ListActors",
      "bedrock-agentcore:ListSessions",
      "bedrock-agentcore:ListMemoryRecords",
      "bedrock-agentcore:GetMemoryRecord",
      "bedrock-agentcore:RetrieveMemoryRecords",
    ]
    resources = ["arn:aws:bedrock-agentcore:*:*:memory/*"]
  }

  statement {
    sid    = "AllowBrowserUse"
    effect = "Allow"
    actions = [
      "bedrock-agentcore:StartBrowserSession",
      "bedrock-agentcore:StopBrowserSession",
      "bedrock-agentcore:GetBrowserSession",
      "bedrock-agentcore:UpdateBrowserStream",
      "bedrock-agentcore:ConnectBrowserAutomationStream",
      "bedrock-agentcore:ConnectBrowserLiveViewStream",
      "bedrock-agentcore:ListBrowserSessions",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "AllowS3CodeRead"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["${aws_s3_bucket.code_runtime.arn}/*"]
  }

  statement {
    sid    = "AllowECRPull"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "runtime" {
  role   = aws_iam_role.runtime.name
  policy = data.aws_iam_policy_document.runtime_policy.json
}

# IAM eventual consistency — without this AgentCore CreateRuntime can fail
# with "role does not have sufficient permissions" on first apply.
resource "time_sleep" "runtime_iam_propagation" {
  create_duration = "10s"
  depends_on      = [aws_iam_role_policy.runtime]
}

# =============================================================================
# GATEWAY IAM
# =============================================================================

resource "aws_iam_role" "gateway" {
  name               = "${var.project_prefix}-gateway"
  assume_role_policy = data.aws_iam_policy_document.agentcore_assume_role.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "gateway_policy" {
  statement {
    sid       = "AllowBedrockModelInvocation"
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowWorkloadIdentityTokenManagement"
    effect = "Allow"
    actions = [
      "bedrock-agentcore:GetWorkloadIdentityToken",
      "bedrock-agentcore:RefreshWorkloadIdentityToken",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "AllowLambdaInvocation"
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.gateway_target.arn]
  }
}

resource "aws_iam_role_policy" "gateway" {
  role   = aws_iam_role.gateway.name
  policy = data.aws_iam_policy_document.gateway_policy.json
}

resource "time_sleep" "gateway_iam_propagation" {
  create_duration = "15s"
  depends_on      = [aws_iam_role_policy.gateway]
}

# =============================================================================
# MEMORY IAM
# =============================================================================

resource "aws_iam_role" "memory" {
  name               = "${var.project_prefix}-memory"
  assume_role_policy = data.aws_iam_policy_document.agentcore_assume_role.json
  tags               = local.common_tags
}

resource "time_sleep" "memory_iam_propagation" {
  create_duration = "10s"
  depends_on      = [aws_iam_role.memory]
}

# =============================================================================
# BROWSER IAM
# =============================================================================

resource "aws_iam_role" "browser" {
  name               = "${var.project_prefix}-browser"
  assume_role_policy = data.aws_iam_policy_document.agentcore_assume_role.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "browser_policy" {
  statement {
    sid       = "AllowCloudWatchLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:log-group:/aws/bedrock-agentcore/*"]
  }
}

resource "aws_iam_role_policy" "browser" {
  role   = aws_iam_role.browser.name
  policy = data.aws_iam_policy_document.browser_policy.json
}

resource "time_sleep" "browser_iam_propagation" {
  create_duration = "30s"
  depends_on      = [aws_iam_role_policy.browser]
}

# =============================================================================
# CODE INTERPRETER IAM
# =============================================================================

resource "aws_iam_role" "code_interpreter" {
  name               = "${var.project_prefix}-code-interpreter"
  assume_role_policy = data.aws_iam_policy_document.agentcore_assume_role.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "code_interpreter_policy" {
  statement {
    sid       = "AllowCloudWatchLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:log-group:/aws/bedrock-agentcore/*"]
  }
}

resource "aws_iam_role_policy" "code_interpreter" {
  role   = aws_iam_role.code_interpreter.name
  policy = data.aws_iam_policy_document.code_interpreter_policy.json
}

resource "time_sleep" "code_interpreter_iam_propagation" {
  create_duration = "30s"
  depends_on      = [aws_iam_role_policy.code_interpreter]
}

# =============================================================================
# LAMBDA IAM (gateway target)
# =============================================================================

resource "aws_iam_role" "lambda" {
  name = "${var.project_prefix}-gateway-target-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
