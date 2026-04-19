output "bucket_ids" {
  description = "Map of bucket key to S3 bucket id."
  value       = { for k, b in aws_s3_bucket.this : k => b.id }
}

output "bucket_arns" {
  description = "Map of bucket key to S3 bucket ARN."
  value       = { for k, b in aws_s3_bucket.this : k => b.arn }
}
