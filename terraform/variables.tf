variable "aws_region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Project name used as a prefix for all resources"
  type        = string
  default     = "image-resizer"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
}

variable "lambda_memory_mb" {
  description = "Lambda function memory in MB"
  type        = number
  default     = 512
}

variable "thumbnail_size" {
  description = "Thumbnail width in pixels"
  type        = number
  default     = 150
}

variable "medium_size" {
  description = "Medium image width in pixels"
  type        = number
  default     = 600
}

variable "large_size" {
  description = "Large image width in pixels"
  type        = number
  default     = 1200
}
