terraform {
  required_version = ">= 1.14"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.18.0"
    }
    awscc = {
      source  = "hashicorp/awscc"
      # awscc 1.87.0 changed AWS::BedrockAgentCore::Gateway ProtocolType to a
      # JSON-string type, but Read returns the plain API value and trips the
      # provider's own validator on refresh. Pin below 1.87 until fixed upstream.
      version = ">= 1.30.0, < 1.87.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0.0"
    }
  }
}
