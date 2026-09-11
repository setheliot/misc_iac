output "code_build_id" {
  description = "SHA-256 build ID of the CODE runtime source files and build script"
  value       = local.code_build_id
}

output "code_runtime_id" {
  description = "ID of the CODE runtime"
  value       = awscc_bedrockagentcore_runtime.code_agent.agent_runtime_id
}

output "code_runtime_arn" {
  description = "ARN of the CODE runtime"
  value       = awscc_bedrockagentcore_runtime.code_agent.agent_runtime_arn
}

output "code_runtime_endpoint_arn" {
  description = "Endpoint ARN of the CODE runtime"
  value       = awscc_bedrockagentcore_runtime_endpoint.code_agent.agent_runtime_endpoint_arn
}

output "container_build_id" {
  description = "SHA-256 build ID of the CONTAINER runtime source files and build script"
  value       = local.container_build_id
}

output "container_runtime_id" {
  description = "ID of the CONTAINER runtime"
  value       = awscc_bedrockagentcore_runtime.container_agent.agent_runtime_id
}

output "container_runtime_arn" {
  description = "ARN of the CONTAINER runtime"
  value       = awscc_bedrockagentcore_runtime.container_agent.agent_runtime_arn
}

output "container_runtime_endpoint_arn" {
  description = "Endpoint ARN of the CONTAINER runtime"
  value       = awscc_bedrockagentcore_runtime_endpoint.container_agent.agent_runtime_endpoint_arn
}

output "memory_id" {
  description = "ID of the semantic memory"
  value       = awscc_bedrockagentcore_memory.semantic_memory.memory_id
}

output "memory_arn" {
  description = "ARN of the semantic memory"
  value       = awscc_bedrockagentcore_memory.semantic_memory.memory_arn
}

output "gateway_id" {
  description = "Gateway identifier"
  value       = awscc_bedrockagentcore_gateway.mcp_gateway.gateway_identifier
}

output "gateway_url" {
  description = "Gateway URL"
  value       = awscc_bedrockagentcore_gateway.mcp_gateway.gateway_url
}

output "gateway_target_id" {
  description = "Gateway target ID"
  value       = aws_bedrockagentcore_gateway_target.lambda_target.target_id
}

output "browser_id" {
  description = "Browser ID"
  value       = awscc_bedrockagentcore_browser_custom.web_browser.browser_id
}

output "browser_arn" {
  description = "Browser ARN"
  value       = awscc_bedrockagentcore_browser_custom.web_browser.browser_arn
}

output "code_interpreter_id" {
  description = "Code interpreter ID"
  value       = awscc_bedrockagentcore_code_interpreter_custom.python_interpreter.code_interpreter_id
}

output "ecr_repository_url" {
  description = "ECR repository URL for the container runtime"
  value       = aws_ecr_repository.container_runtime.repository_url
}

output "code_runtime_s3_bucket" {
  description = "S3 bucket holding the code runtime artifact"
  value       = aws_s3_bucket.code_runtime.id
}
