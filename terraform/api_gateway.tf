# ── HTTP API Gateway (v2) ─────────────────────────────────────────────────────
resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_headers = ["Content-Type", "Authorization"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_origins = ["*"]
  }

  tags = merge(local.app_tags, {
    Project = var.project_name
  })
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  # /presign and /results are intentionally public (anyone can try the demo).
  # Throttling is a cost guardrail, not an access-control change: it caps how
  # fast an unauthenticated caller can flood /presign and run up S3 upload +
  # Lambda-invocation cost. Limits apply across the whole stage (all callers
  # combined). API Gateway throttling is a free feature - no billable resource.
  default_route_settings {
    throttling_rate_limit  = 5  # sustained requests/sec
    throttling_burst_limit = 10 # short burst ceiling
  }
}

# ── API Lambda (presigned URL + results lookup) ───────────────────────────────
resource "aws_iam_role" "api_lambda_exec" {
  name = "${var.project_name}-api-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "api_lambda_basic" {
  role       = aws_iam_role.api_lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "api_lambda_s3" {
  name = "${var.project_name}-api-lambda-s3"
  role = aws_iam_role.api_lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "GeneratePresignedUpload"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.uploads.arn}/originals/*"
      },
      {
        Sid      = "ListOutputs"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.outputs.arn
        Condition = {
          StringLike = { "s3:prefix" = ["resized/*"] }
        }
      },
      {
        Sid      = "ReadOutputs"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.outputs.arn}/resized/*"
      }
    ]
  })
}

data "archive_file" "api_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/../lambda/api_function.zip"

  source {
    content  = <<-EOT
import boto3
import json
import os
import uuid
from botocore.client import Config
from botocore.exceptions import ClientError

REGION = os.environ.get("AWS_REGION", "eu-west-1")
s3 = boto3.client(
    "s3",
    region_name=REGION,
    endpoint_url=f"https://s3.{REGION}.amazonaws.com",
    config=Config(signature_version="s3v4", s3={"addressing_style": "virtual"}),
)
UPLOAD_BUCKET = os.environ["UPLOAD_BUCKET"]
OUTPUT_BUCKET = os.environ["OUTPUT_BUCKET"]

def lambda_handler(event, context):
    path = event.get("rawPath", "")
    method = event.get("requestContext", {}).get("http", {}).get("method", "")

    headers = {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
    }

    if path == "/presign" and method == "GET":
        params = event.get("queryStringParameters") or {}
        filename = params.get("filename", f"{uuid.uuid4()}.jpg")
        key = f"originals/{uuid.uuid4()}-{filename}"

        url = s3.generate_presigned_url(
            "put_object",
            Params={"Bucket": UPLOAD_BUCKET, "Key": key, "ContentType": "image/jpeg"},
            ExpiresIn=300,
        )
        return {
            "statusCode": 200,
            "headers": headers,
            "body": json.dumps({"url": url, "key": key}),
        }

    if path == "/results" and method == "GET":
        params = event.get("queryStringParameters") or {}
        key = params.get("key", "")
        basename = key.replace("originals/", "").rsplit(".", 1)[0]
        prefix = f"resized/{basename}/"

        # Only declare "done" when all three expected variants have been written.
        # Otherwise the frontend can race the resizer and see only the first
        # variant (thumb) that gets uploaded.
        expected = ["thumb", "medium", "large"]

        try:
            resp = s3.list_objects_v2(Bucket=OUTPUT_BUCKET, Prefix=prefix)
            objects = resp.get("Contents", [])
            found = {obj["Key"].split("/")[-1].replace(".jpg", ""): obj["Key"] for obj in objects}

            if not set(expected).issubset(found.keys()):
                return {"statusCode": 202, "headers": headers, "body": json.dumps({"status": "processing"})}

            results = {
                name: s3.generate_presigned_url(
                    "get_object",
                    Params={"Bucket": OUTPUT_BUCKET, "Key": found[name]},
                    ExpiresIn=3600,
                )
                for name in expected
            }

            return {"statusCode": 200, "headers": headers, "body": json.dumps({"status": "done", "images": results})}
        except ClientError as e:
            return {"statusCode": 500, "headers": headers, "body": json.dumps({"error": str(e)})}

    return {"statusCode": 404, "headers": headers, "body": json.dumps({"error": "Not found"})}
EOT
    filename = "api_handler.py"
  }
}

resource "aws_lambda_function" "api" {
  function_name    = "${var.project_name}-api"
  role             = aws_iam_role.api_lambda_exec.arn
  handler          = "api_handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 10
  memory_size      = 128
  filename         = data.archive_file.api_lambda_zip.output_path
  source_code_hash = data.archive_file.api_lambda_zip.output_base64sha256

  environment {
    variables = {
      UPLOAD_BUCKET = aws_s3_bucket.uploads.bucket
      OUTPUT_BUCKET = aws_s3_bucket.outputs.bucket
    }
  }

  tags = merge(local.app_tags, { Project = var.project_name })
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

resource "aws_apigatewayv2_integration" "api_lambda" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "presign" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /presign"
  target    = "integrations/${aws_apigatewayv2_integration.api_lambda.id}"
}

resource "aws_apigatewayv2_route" "results" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /results"
  target    = "integrations/${aws_apigatewayv2_integration.api_lambda.id}"
}
