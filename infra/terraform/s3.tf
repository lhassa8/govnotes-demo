# ------------------------------------------------------------------------
# Application S3 buckets
#
# Six buckets at varying maturity. The set is intentionally mixed because
# real mid-journey FedRAMP posture isn't binary — different teams ship
# bucket configurations on different timelines, and the encryption /
# public-access / versioning postures lag behind one another in
# predictable ways.
#
# Coverage table (deliberate gaps, see DELIBERATE_GAPS.md):
#
#   bucket             encryption  kms_key      public_block  versioning
#   ----------------   ----------  -----------  ------------  ----------
#   app_uploads        ✓ AES256    CMK (app)    ✓ all=true    ✓
#   static_assets      ✓ AES256    AWS-managed  ✓ all=true    ✓
#   internal_reports   ✓ AES256    CMK (reports) ✓ all=true   ✗ (partial)
#   ml_training_data   ✓ AES256    AWS-managed  ✗ (partial)   ✗
#   legacy_export      ✗ (gap)     —            ✓ all=true    ✗
#   temp_data_pipeline ✗ (gap)     —            ✗ (gap)       ✗
#
# This isn't aspirational — it's exactly the bucket-by-bucket variance
# a 3PAO would surface in a real scoping meeting. KSI-SVC-PRR (CMK
# usage) is `partial` here — most buckets use CMKs, two use AWS-managed
# keys, two have no encryption block at all.
# ------------------------------------------------------------------------

# --- bucket 1: app_uploads — fully posture-compliant ---------------------

resource "aws_s3_bucket" "app_uploads" {
  bucket = "${local.name_prefix}-app-uploads-${random_id.suffix.hex}"

  tags = {
    Name               = "${local.name_prefix}-app-uploads"
    DataClassification = "moderate"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app_uploads" {
  bucket = aws_s3_bucket.app_uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.app.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "app_uploads" {
  bucket                  = aws_s3_bucket.app_uploads.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "app_uploads" {
  bucket = aws_s3_bucket.app_uploads.id
  versioning_configuration {
    status = "Enabled"
  }
}

# --- bucket 2: static_assets — encrypted but with AWS-managed key --------
# AWS-managed keys (sse_algorithm = "AES256") are KMS-encrypted but not
# customer-controlled. KSI-SVC-PRR wants CMKs on data assets; this one
# is borderline because static assets are public-read content with no
# data classification. Documented as partial.

resource "aws_s3_bucket" "static_assets" {
  bucket = "${local.name_prefix}-static-assets-${random_id.suffix.hex}"

  tags = {
    Name               = "${local.name_prefix}-static-assets"
    DataClassification = "public"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "static_assets" {
  bucket = aws_s3_bucket.static_assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "static_assets" {
  bucket                  = aws_s3_bucket.static_assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "static_assets" {
  bucket = aws_s3_bucket.static_assets.id
  versioning_configuration {
    status = "Enabled"
  }
}

# --- bucket 3: internal_reports — CMK + public-block, missing versioning -

resource "aws_s3_bucket" "internal_reports" {
  bucket = "${local.name_prefix}-internal-reports-${random_id.suffix.hex}"

  tags = {
    Name               = "${local.name_prefix}-internal-reports"
    DataClassification = "moderate"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "internal_reports" {
  bucket = aws_s3_bucket.internal_reports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.reports.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "internal_reports" {
  bucket                  = aws_s3_bucket.internal_reports.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# (no aws_s3_bucket_versioning — finance team requested current-only
# semantics for cost; tracked as a partial in DELIBERATE_GAPS)

# --- bucket 4: ml_training_data — encrypted, public-block PARTIAL --------
# block_public_acls + ignore_public_acls only. block_public_policy and
# restrict_public_buckets left default (= false). Surfaces as partial
# public-access-block posture rather than a binary gap.

resource "aws_s3_bucket" "ml_training_data" {
  bucket = "${local.name_prefix}-ml-training-${random_id.suffix.hex}"

  tags = {
    Name               = "${local.name_prefix}-ml-training"
    DataClassification = "low"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ml_training_data" {
  bucket = aws_s3_bucket.ml_training_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "ml_training_data" {
  bucket             = aws_s3_bucket.ml_training_data.id
  block_public_acls  = true
  ignore_public_acls = true
  # block_public_policy + restrict_public_buckets intentionally omitted;
  # ML team needs cross-account reads from a partner-bucket ARN that
  # gets blocked by restrict_public_buckets. Tracked for cleanup once
  # the partner switches to a federated role.
}

# --- bucket 5: legacy_export — NO encryption block, public-block ✓ -------
# Pre-2025 bucket carrying nightly export dumps for the reporting
# partner. Encryption was never enabled because the partner consumes
# unencrypted CSVs and we punted on a re-export pipeline.

resource "aws_s3_bucket" "legacy_export" {
  bucket = "${local.name_prefix}-legacy-export-${random_id.suffix.hex}"

  tags = {
    Name               = "${local.name_prefix}-legacy-export"
    DataClassification = "moderate"
  }
}

resource "aws_s3_bucket_public_access_block" "legacy_export" {
  bucket                  = aws_s3_bucket.legacy_export.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# (no aws_s3_bucket_server_side_encryption_configuration — gap)

# --- bucket 6: temp_data_pipeline — NO encryption AND NO public-block ----
# Dev-team pipeline scratch bucket. Uses a 7-day lifecycle expiration
# (defined in app code, not Terraform), so contents churn weekly.
# Surfaces both encryption gap AND public-block gap; a real ops team
# would reach this third on the priority queue.

resource "aws_s3_bucket" "temp_data_pipeline" {
  bucket = "${local.name_prefix}-temp-pipeline-${random_id.suffix.hex}"

  tags = {
    Name               = "${local.name_prefix}-temp-pipeline"
    DataClassification = "internal"
  }
}

# (no encryption block; no public_access_block; no versioning — full gap stack)
