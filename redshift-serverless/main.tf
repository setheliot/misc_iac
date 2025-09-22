
provider "aws" {
  region = var.region
}

resource "aws_redshiftserverless_namespace" "example" {
  namespace_name         = var.namespace_name
  #db_name                = "mydb"
  manage_admin_password = true
  tags                   = local.tags
  kms_key_id             = aws_kms_key.redshift.arn
}

resource "aws_redshiftserverless_workgroup" "example" {
  workgroup_name     = var.workgroup_name
  namespace_name     = aws_redshiftserverless_namespace.example.namespace_name
  base_capacity      = var.base_capacity
  max_capacity       = var.max_capacity
  subnet_ids         = module.vpc.redshift_subnets
  security_group_ids = [module.security_group.security_group_id]
  tags               = local.tags
}

resource "aws_redshiftserverless_endpoint_access" "example" {
  workgroup_name         = aws_redshiftserverless_workgroup.example.workgroup_name
  endpoint_name          = var.endpoint_name
  subnet_ids             = module.vpc.redshift_subnets
  vpc_security_group_ids = [module.security_group.security_group_id]
}