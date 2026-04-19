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

# ------------------------------------------------------------------------
# S3 buckets
# ------------------------------------------------------------------------

resource "aws_s3_bucket" "artifacts" {
  bucket = "${local.name_prefix}-artifacts-${random_id.suffix.hex}"

  tags = {
    Name    = "${local.name_prefix}-artifacts"
    Purpose = "build-artifacts"
  }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.app.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------------------
# Static assets bucket — serves marketing imagery, public product icons,
# and the like. Not customer data, but still in-boundary.
# ------------------------------------------------------------------------

resource "aws_s3_bucket" "assets" {
  bucket = "${local.name_prefix}-assets-${random_id.suffix.hex}"

  tags = {
    Name    = "${local.name_prefix}-assets"
    Purpose = "static-assets"
  }
}

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------------------
# Backups bucket — point-in-time exports land here before lifecycle to
# Glacier. Versioning on, KMS on, access via backup role only.
# ------------------------------------------------------------------------

resource "aws_s3_bucket" "backups" {
  bucket = "${local.name_prefix}-backups-${random_id.suffix.hex}"

  tags = {
    Name    = "${local.name_prefix}-backups"
    Purpose = "point-in-time-backups"
  }
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.app.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------------------
# User uploads bucket — attachments on notes (images, PDFs, small docs).
# Accessed via short-lived presigned URLs issued by the app.
# ------------------------------------------------------------------------

resource "aws_s3_bucket" "user_uploads" {
  bucket = "${local.name_prefix}-user-uploads-${random_id.suffix.hex}"

  tags = {
    Name    = "${local.name_prefix}-user-uploads"
    Purpose = "customer-attachments"
  }
}

resource "aws_s3_bucket_public_access_block" "user_uploads" {
  bucket                  = aws_s3_bucket.user_uploads.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
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

  backup_retention_period = 14
  backup_window           = "04:00-05:00"
  maintenance_window      = "sun:05:30-sun:06:30"
  copy_tags_to_snapshot   = true
  deletion_protection     = true
  skip_final_snapshot     = false
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
# customer-facing and does not store regulated data, so we sized it small.
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

  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = false

  tags = {
    Name = "${local.name_prefix}-analytics-db"
  }
}
