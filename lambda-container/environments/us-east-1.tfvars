aws_region          = "us-east-1"
environment         = "demo"
project_name        = "guestbook-app"
ecr_container_image = "guestbook-app:lambda"
dynamodb_table_name = "guestbook-entries"
lambda_memory_size  = 512
lambda_timeout      = 30
