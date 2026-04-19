# ------------------------------------------------------------------------
# KMS keys
# ------------------------------------------------------------------------

resource "aws_kms_key" "app" {
  description             = "CMK for Govnotes app data (RDS, app logs, app S3)"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name = "${local.name_prefix}-app-cmk"
  }
}

resource "aws_kms_alias" "app" {
  name          = "alias/${local.name_prefix}-app"
  target_key_id = aws_kms_key.app.key_id
}

resource "aws_kms_key" "logs" {
  description             = "CMK for CloudTrail and other audit logs"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_logs.json

  tags = {
    Name = "${local.name_prefix}-logs-cmk"
  }
}

resource "aws_kms_alias" "logs" {
  name          = "alias/${local.name_prefix}-logs"
  target_key_id = aws_kms_key.logs.key_id
}

# CMK used for the static-assets bucket. Not a high-sensitivity bucket.
# Rotation is being handled manually on a 12-month cadence, TBD moving
# to automatic once we confirm the manual process with the ops team.
resource "aws_kms_key" "assets" {
  description              = "CMK for Govnotes static-assets bucket"
  deletion_window_in_days  = 30
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  enable_key_rotation      = false

  tags = {
    Name = "${local.name_prefix}-assets-cmk"
  }
}

resource "aws_kms_alias" "assets" {
  name          = "alias/${local.name_prefix}-assets"
  target_key_id = aws_kms_key.assets.key_id
}

# CMK for the internal-reports bucket that the finance analytics team
# reads for cross-service reporting. We loosened the key policy a bit
# to unblock their workflow while we sort out per-service roles.
resource "aws_kms_key" "reports" {
  description             = "CMK for the internal finance-analytics reports bucket"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_reports.json

  tags = {
    Name = "${local.name_prefix}-reports-cmk"
  }
}

resource "aws_kms_alias" "reports" {
  name          = "alias/${local.name_prefix}-reports"
  target_key_id = aws_kms_key.reports.key_id
}

data "aws_iam_policy_document" "kms_logs" {
  statement {
    sid    = "EnableRootPermissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudTrail"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions = [
      "kms:GenerateDataKey*",
      "kms:Decrypt",
      "kms:DescribeKey"
    ]

    resources = ["*"]
  }
}

data "aws_iam_policy_document" "kms_reports" {
  statement {
    sid    = "EnableRootPermissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  # Any principal in the account can use this key for the analytics ETL
  # flow. Temporary — revisit once the per-service role model lands.
  statement {
    sid    = "AllowAccountUse"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [local.account_id]
    }
  }
}

# ------------------------------------------------------------------------
# S3 buckets — created through the storage module.
#
# Per-bucket configuration is declared below. Callers are responsible
# for opting into encryption and versioning per bucket.
# ------------------------------------------------------------------------

module "storage" {
  source = "./modules/storage"

  name_prefix = local.name_prefix
  suffix      = random_id.suffix.hex

  buckets = {
    artifacts = {
      purpose     = "build-artifacts"
      kms_key_arn = aws_kms_key.app.arn
      versioning  = true
    }
    assets = {
      purpose    = "static-assets"
      sse_s3     = true
      versioning = true
    }
    backups = {
      purpose     = "point-in-time-backups"
      kms_key_arn = aws_kms_key.app.arn
      versioning  = true
    }
    user_uploads = {
      purpose = "customer-attachments"
    }
    internal_reports = {
      purpose     = "finance-analytics-reports"
      kms_key_arn = aws_kms_key.reports.arn
      versioning  = true
    }
  }
}

locals {
  artifacts_bucket_id        = module.storage.bucket_ids["artifacts"]
  artifacts_bucket_arn       = module.storage.bucket_arns["artifacts"]
  assets_bucket_id           = module.storage.bucket_ids["assets"]
  assets_bucket_arn          = module.storage.bucket_arns["assets"]
  backups_bucket_id          = module.storage.bucket_ids["backups"]
  backups_bucket_arn         = module.storage.bucket_arns["backups"]
  user_uploads_bucket_id     = module.storage.bucket_ids["user_uploads"]
  user_uploads_bucket_arn    = module.storage.bucket_arns["user_uploads"]
  internal_reports_bucket_id = module.storage.bucket_ids["internal_reports"]
}

# ------------------------------------------------------------------------
# RDS — primary app database
# ------------------------------------------------------------------------

resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnets"
  subnet_ids = [for s in aws_subnet.private_data : s.id]

  tags = {
    Name = "${local.name_prefix}-db-subnets"
  }
}

resource "aws_secretsmanager_secret" "db_url" {
  name                    = "${local.name_prefix}/db-url"
  kms_key_id              = aws_kms_key.app.arn
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret" "jwt_signing_key" {
  name                    = "${local.name_prefix}/jwt-signing-key"
  kms_key_id              = aws_kms_key.app.arn
  recovery_window_in_days = 7
}

resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_db_instance" "app" {
  identifier     = "${local.name_prefix}-app-db"
  engine         = "postgres"
  engine_version = "15.6"
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = 1000
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.app.arn

  db_name  = "govnotes"
  username = var.db_username
  password = random_password.db.result
  port     = 5432

  multi_az               = true
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]

  backup_retention_period   = 30
  backup_window             = "04:00-05:00"
  maintenance_window        = "sun:05:30-sun:06:30"
  copy_tags_to_snapshot     = true
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name_prefix}-app-db-final"

  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.app.arn

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  tags = {
    Name = "${local.name_prefix}-app-db"
  }
}

# ------------------------------------------------------------------------
# RDS — analytics database
#
# Secondary Postgres the analytics team uses for the internal reporting
# dashboards. Loaded from the primary via a nightly ETL job. Not
# customer-facing and does not store regulated data, so we sized it
# small and set a short retention to keep costs down.
# ------------------------------------------------------------------------

resource "aws_db_instance" "analytics" {
  identifier     = "${local.name_prefix}-analytics-db"
  engine         = "postgres"
  engine_version = "15.6"
  instance_class = "db.t4g.medium"

  allocated_storage = 100
  storage_type      = "gp3"
  storage_encrypted = true
  kms_key_id        = aws_kms_key.app.arn

  db_name  = "analytics"
  username = "analytics_ro"
  password = random_password.db.result
  port     = 5432

  multi_az               = false
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]

  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false

  tags = {
    Name = "${local.name_prefix}-analytics-db"
  }
}
