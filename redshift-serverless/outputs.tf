output "namespace_id" {
  value = aws_redshiftserverless_namespace.example.id
}

output "workgroup_id" {
  value = aws_redshiftserverless_workgroup.example.id
}

output "endpoint" {
  value = aws_redshiftserverless_endpoint_access.example.endpoint_name
}