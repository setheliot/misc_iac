# ===== dynamodb.tf =====
# DynamoDB table for guestbook entries
resource "aws_dynamodb_table" "guestbook" {
  name             = "${var.dynamodb_table_name}-${var.environment}"
  billing_mode     = "PAY_PER_REQUEST"
  stream_enabled   = true
  stream_view_type = "NEW_IMAGE"

  point_in_time_recovery {
    enabled                 = true
    recovery_period_in_days = 5
  }

  hash_key = "GuestID"

  attribute {
    name = "GuestID"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  global_secondary_index {
    name            = "timestamp-index"
    hash_key        = "timestamp"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = false
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-dynamodb"
    }
  )
}