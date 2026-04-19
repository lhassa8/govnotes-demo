terraform {
  required_version = ">= 1.6.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }
}

locals {
  bucket_names = {
    for k, _ in var.buckets : k => "${var.name_prefix}-${k}-${var.suffix}"
  }
}

resource "aws_s3_bucket" "this" {
  for_each = var.buckets
  bucket   = local.bucket_names[each.key]

  tags = merge(
    var.tags,
    {
      Name    = local.bucket_names[each.key]
      Purpose = each.value.purpose
    },
  )
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = {
    for k, v in var.buckets : k => v
    if v.kms_key_arn != null || v.sse_s3
  }

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = each.value.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = each.value.kms_key_arn
    }
    bucket_key_enabled = each.value.kms_key_arn != null
  }
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = {
    for k, v in var.buckets : k => v
    if v.versioning
  }

  bucket = aws_s3_bucket.this[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}
