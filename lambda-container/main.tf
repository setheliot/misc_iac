# main.tf - Main Terraform configuration
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data source for AWS account ID
data "aws_caller_identity" "current" {}

# Data source for AWS region
data "aws_region" "current" {}

# Local variables
locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  base_path  = "/${var.environment}"

  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }

  ecr_prefix_current = "${local.account_id}.dkr.ecr.${local.region}.amazonaws.com"

  # Final image URI used by Lambda:
  image_uri = "${local.ecr_prefix_current}/${var.ecr_container_image}"
}
