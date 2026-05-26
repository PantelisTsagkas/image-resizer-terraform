output "api_base_url" {
  description = "Base URL of the HTTP API — paste this into frontend/index.html"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "upload_bucket_name" {
  description = "S3 bucket that receives original uploads"
  value       = aws_s3_bucket.uploads.bucket
}

output "output_bucket_name" {
  description = "S3 bucket that stores resized images"
  value       = aws_s3_bucket.outputs.bucket
}

output "resizer_lambda_name" {
  description = "Name of the image-resizing Lambda function"
  value       = aws_lambda_function.resizer.function_name
}

output "api_lambda_name" {
  description = "Name of the API Lambda function"
  value       = aws_lambda_function.api.function_name
}
