# ------------------------------------------------------------------------
# CloudTrail log bucket
# ------------------------------------------------------------------------

resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${local.name_prefix}-cloudtrail-${random_id.suffix.hex}"
  force_destroy = false

  tags = {
    Name    = "${local.name_prefix}-cloudtrail"
    Purpose = "audit-logs"
  }
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.logs.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "cloudtrail_bucket" {
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:cloudtrail:${var.region}:${local.account_id}:trail/${local.name_prefix}-trail"]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${local.account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:cloudtrail:${var.region}:${local.account_id}:trail/${local.name_prefix}-trail"]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket.json
}

# ------------------------------------------------------------------------
# CloudTrail
#
# Captures management events across all regions. Data events for S3
# and Lambda are deferred to the Q2 cost review; log-file validation
# is pending the SIEM pipeline work. Once the SIEM integration ships
# we'll flip validation on and add the data-event selectors.
# ------------------------------------------------------------------------

resource "aws_cloudtrail" "main" {
  name           = "${local.name_prefix}-trail"
  s3_bucket_name = aws_s3_bucket.cloudtrail.id

  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = false

  kms_key_id = aws_kms_key.logs.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail]

  tags = {
    Name = "${local.name_prefix}-trail"
  }
}

# ------------------------------------------------------------------------
# CloudWatch log groups for platform services
# ------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/govnotes/${var.environment}/vpc-flow-logs"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.logs.arn
}

resource "aws_iam_role" "flow_logs" {
  name = "${local.name_prefix}-flow-logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "${local.name_prefix}-flow-logs"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"
    }]
  })
}

resource "aws_flow_log" "vpc" {
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-vpc-flow-logs"
  }
}

# ------------------------------------------------------------------------
# Observability module — CloudWatch alarms for ECS, RDS, ALB.
#
# Wrapped into a module so the alarm set composes cleanly across future
# workloads. Every alarm declared inside the module surfaces only via
# `efterlev scan --plan plan.json` (HCL-mode detectors don't follow into
# module bodies); a customer evaluating Efterlev can compare HCL-mode
# evidence count to plan-mode evidence count against this codebase to
# see the module-composition lift firsthand.
# ------------------------------------------------------------------------

module "observability" {
  source = "./modules/observability"

  name_prefix      = local.name_prefix
  ecs_cluster_name = aws_ecs_cluster.main.name
  ecs_service_name = aws_ecs_service.app.name
  rds_instance_id  = aws_db_instance.app.id
  alb_arn_suffix   = aws_lb.app.arn_suffix

  # alarm_actions intentionally empty — wiring SNS topics for paging is
  # tracked in a follow-up. The alarms still fire on the metrics; they
  # just don't notify anyone yet.
  alarm_actions = []

  tags = {
    Name = "${local.name_prefix}-observability"
  }
}
