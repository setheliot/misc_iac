variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
}

variable "project_prefix" {
  description = "Prefix applied to resource names. Keep short; some AWS resources have low name-length caps."
  type        = string
  default     = "agentcore-demo"
}

variable "container_image_tag" {
  description = "Tag used for the container runtime image pushed to ECR"
  type        = string
  default     = "latest"
}

variable "bedrock_model_id" {
  description = "Bedrock model ID the container agent uses (passed as MODEL_ID env var)"
  type        = string
  default     = "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
}

variable "code_agent_log_level" {
  description = "LOG_LEVEL env var for the code-agent runtime"
  type        = string
  default     = "INFO"
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
