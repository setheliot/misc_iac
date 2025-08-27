# ===== variables.tf =====
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, demo, prod)"
  type        = string
  default     = "demo"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "guestbook-app"
}

# Choose one ecr_container_repository_tag or container_image_uri
# and set only the one you want to use

# Prefer this when you want to use an image in the CURRENT account/region ECR
variable "ecr_container_repository_tag" {
  description = "repository:tag of ECR image - only works is in same account and Region"
  type        = string
  default     = null
  #default     = "guestbook-app:lambda"
}

# Fallback: any full container image URI (ECR in another account/region, Docker Hub, etc.)
variable "container_image_uri" {
  description = "URI of the container image to use for Lambda (e.g., from ECR or Docker Hub)"
  type        = string
  default     = null
  #default     = "docker.io/nginxdemos/hello"
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  type        = string
  default     = "guestbook-entries"
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda function"
  type        = number
  default     = 512
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 30
}