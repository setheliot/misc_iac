resource "random_string" "code_bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket" "code_runtime" {
  bucket        = "${var.project_prefix}-${replace(local.code_runtime_name, "_", "-")}-code-${random_string.code_bucket_suffix.result}"
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_bucket_versioning" "code_runtime" {
  bucket = aws_s3_bucket.code_runtime.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "code_runtime" {
  bucket = aws_s3_bucket.code_runtime.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "code_runtime" {
  bucket = aws_s3_bucket.code_runtime.id

  rule {
    id     = "delete-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
