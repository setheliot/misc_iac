# Remote backend for storing Terraform state

# You need an S3 bucket and DynamoDB table in the same AWS account where you will deploy your resources
# These must be the in the AWS Region corresponding to the value below
# This can be a _different_ Region than where you deploy your resources
# You can change this Region below, as long as the S3 bucket and DDB table also go in that Region

# Update `bucket` below to the name of the S3 bucket you will use. This usually will be a new bucket
# but can also be one which you already use for Terraform state

terraform {
  backend "s3" {
    bucket         = "terraform-state-bucket-demo-uniqueid"
    key            = "lambda-demo/terraform.tfstate"
    use_lockfile   = true
    region         = "us-east-1"
    encrypt        = false
  }
}