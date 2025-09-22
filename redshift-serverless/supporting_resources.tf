################################################################################
# Supporting Resources
################################################################################

data "aws_availability_zones" "available" {}

locals {
  name = "rs-serverless-seth-20250922"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  # s3_prefix = "redshift/${local.name}/"

  tags = {
    Name       = local.name
    GithubRepo = "misc_iac"
    CreatedBy  = "seliot"
    Purpose    = "Redshift Serverless demo"
  }
}


module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.2"

  name = local.name
  cidr = local.vpc_cidr

  azs              = local.azs
  private_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  redshift_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 10)]

  # Use subnet group created by module
  create_redshift_subnet_group = false

  tags = local.tags
}

module "security_group" {
  source  = "terraform-aws-modules/security-group/aws//modules/redshift"
  version = "~> 5.0"

  name        = local.name
  description = "Redshift security group"
  vpc_id      = module.vpc.vpc_id

  # Allow ingress rules to be accessed only within current VPC
  ingress_rules       = ["redshift-tcp"]
  ingress_cidr_blocks = [module.vpc.vpc_cidr_block]

  # Allow all rules for all protocols
  egress_rules = ["all-all"]

  tags = local.tags
}

resource "aws_kms_key" "redshift" {
  description             = "${local.name} - CMK for Redshift cluster"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = local.tags
}
