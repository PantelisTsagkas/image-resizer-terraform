# ── Package the Lambda source code ───────────────────────────────────────────
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda"
  output_path = "${path.module}/../lambda/function.zip"
  excludes    = ["requirements.txt", "function.zip"]
}

# ── Pillow Lambda layer (Klayers — fetched at plan time) ─────────────────────
# Source: https://github.com/keithrozario/Klayers
data "http" "pillow_layer" {
  url = "https://api.klayers.cloud/api/v2/p3.12/layers/${var.aws_region}/Pillow"
}

locals {
  pillow_layer_arn = one([
    for layer in jsondecode(data.http.pillow_layer.response_body) : layer.arn
    if try(layer.deployStatus, "") == "latest"
  ])
}

# ── Lambda function ───────────────────────────────────────────────────────────
resource "aws_lambda_function" "resizer" {
  function_name = "${var.project_name}-resizer"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_mb

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  layers = [local.pillow_layer_arn]

  environment {
    variables = {
      OUTPUT_BUCKET  = aws_s3_bucket.outputs.bucket
      THUMBNAIL_SIZE = tostring(var.thumbnail_size)
      MEDIUM_SIZE    = tostring(var.medium_size)
      LARGE_SIZE     = tostring(var.large_size)
    }
  }

  tags = merge(local.app_tags, {
    Project = var.project_name
  })
}

# ── CloudWatch log group with retention ──────────────────────────────────────
resource "aws_cloudwatch_log_group" "resizer" {
  name              = "/aws/lambda/${aws_lambda_function.resizer.function_name}"
  retention_in_days = 7

  tags = {
    Project = var.project_name
  }
}
