# Lambda Container Guestbook Application

Serverless guestbook application using AWS Lambda with container images, API Gateway, and DynamoDB.

## Architecture

- **AWS Lambda** (ARM64) - Containerized application runtime
- **API Gateway HTTP API** - REST API endpoints with CORS
- **DynamoDB** - NoSQL database with GSI and streams
- **CloudWatch** - Logging for Lambda and API Gateway
- **IAM** - Least privilege access roles

## Container Image Options

Choose one of two container image sources:

### ECR (Same Account/Region)
```hcl
ecr_container_repository_tag = "guestbook-app:lambda"
```

### External Registry
```hcl
container_image_uri = "docker.io/nginxdemos/hello"
```

## Quick Start

1. **Configure variables**:
   ```bash
   cp environments/terraform.tfvars.example environments/terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

2. **Deploy**:
   ```bash
   terraform init
   terraform plan -var-file="environments/terraform.tfvars"
   terraform apply -var-file="environments/terraform.tfvars"
   ```

3. **Test**:
   ```bash
   curl $(terraform output -raw api_endpoint)
   ```

## Configuration

### Required Variables
- `aws_region` - AWS deployment region
- `container_image_uri` OR `ecr_container_repository_tag` - Container image source

### Optional Variables
- `environment` - Environment name (default: "demo")
- `project_name` - Project identifier (default: "guestbook-app")
- `lambda_memory_size` - Lambda memory in MB (default: 512)
- `lambda_timeout` - Lambda timeout in seconds (default: 30)

## DynamoDB Schema

**Table**: `guestbook-entries-{environment}`
- **Hash Key**: `GuestID` (String)
- **GSI**: `timestamp-index` on `timestamp` (Number)
- **Features**: Point-in-time recovery, DynamoDB Streams

## API Endpoints

- **Base URL**: `{api_endpoint}/{environment}`
- **Routes**: Catch-all `$default` route forwards to Lambda
- **CORS**: Enabled for all origins and methods

## Environment Variables (Lambda)

- `DDB_TABLE` - DynamoDB table name
- `ENVIRONMENT` - Deployment environment
- `NODE_NAME` - Fixed to "serverless"
- `AWS_LWA_PORT` - Lambda Web Adapter port (8080)
- `BASE_PATH` - API Gateway stage path

## Outputs

- `api_endpoint` - API Gateway invoke URL
- `dynamodb_table_name` - DynamoDB table name
- `lambda_function_name` - Lambda function name
- `lambda_function_arn` - Lambda function ARN

## Remote State (Optional)

Uncomment `backend.tf` and configure S3 backend for team collaboration.