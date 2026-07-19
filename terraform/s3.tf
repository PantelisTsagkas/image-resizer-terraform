# ── Upload bucket (receives original images from the frontend) ────────────────
resource "aws_s3_bucket" "uploads" {
  bucket        = "${var.project_name}-uploads-${random_id.suffix.hex}"
  force_destroy = true

  tags = merge(local.app_tags, {
    Name    = "${var.project_name}-uploads"
    Project = var.project_name
  })
}

resource "aws_s3_bucket_cors_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST", "GET"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket                  = aws_s3_bucket.uploads.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    id     = "expire-originals"
    status = "Enabled"

    filter {}

    expiration {
      days = 1
    }
  }
}

# Allow S3 to invoke Lambda when a new object lands in the uploads bucket
resource "aws_s3_bucket_notification" "uploads_trigger" {
  bucket = aws_s3_bucket.uploads.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.resizer.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "originals/"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

# ── Output bucket (stores the three resized variants) ─────────────────────────
resource "aws_s3_bucket" "outputs" {
  bucket        = "${var.project_name}-outputs-${random_id.suffix.hex}"
  force_destroy = true

  tags = merge(local.app_tags, {
    Name    = "${var.project_name}-outputs"
    Project = var.project_name
  })
}

resource "aws_s3_bucket_public_access_block" "outputs" {
  bucket                  = aws_s3_bucket.outputs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "outputs" {
  bucket = aws_s3_bucket.outputs.id

  rule {
    id     = "expire-resized"
    status = "Enabled"

    filter {}

    expiration {
      days = 7
    }
  }
}
