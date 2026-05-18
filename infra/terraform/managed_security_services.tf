# ------------------------------------------------------------------------
# Managed security services
#
# A real FedRAMP mid-journey boundary will have some things right.
# These are the resources that exercise AWS managed-security services
# the team got around to enabling — detector hits that flip the
# corresponding KSIs from `not_implemented` (no resource present) to
# `implemented` (resource present + correctly configured).
#
# The variance is intentional: GuardDuty, AccessAnalyzer, and the
# federated identity provider are clean wins. AWS Config is enabled
# with a small but real rule set — KSI-SVC-ACM (configuration
# management) flips to `implemented` for "resource present" but a
# 3PAO would still want to see the rule set expanded to the full
# FedRAMP-Moderate Config conformance pack. WAF is attached to the
# primary ALB with rate-limiting + managed rule groups; the team
# hasn't yet enabled geo-blocking (that's still tracked).
# ------------------------------------------------------------------------

# --- GuardDuty: organization-level threat detection ---------------------
# KSI-INR-RIR, KSI-MLA-LET. Detector finding flow lands in Security Hub
# (also wired below) which feeds the platform-security inbox via the
# EventBridge rule defined later in this file.

resource "aws_guardduty_detector" "main" {
  enable = true

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = false
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = false
        }
      }
    }
  }

  finding_publishing_frequency = "FIFTEEN_MINUTES"

  tags = {
    Name = "${local.name_prefix}-guardduty"
  }
}

# --- AccessAnalyzer: external-access detection across the account -------
# KSI-IAM-AAM, KSI-IAM-ELP. Catches IAM policies or resource policies
# that grant access to external principals (the kind of finding the
# `kms_reports` key's broad policy would surface).

resource "aws_accessanalyzer_analyzer" "main" {
  analyzer_name = "${local.name_prefix}-account-analyzer"
  type          = "ACCOUNT"

  tags = {
    Name = "${local.name_prefix}-access-analyzer"
  }
}

# --- AWS Config: continuous configuration evaluation --------------------
# KSI-SVC-ACM. Recorder + delivery channel + a small set of managed
# rules. Rule set is intentionally narrow (not a full FedRAMP-Moderate
# conformance pack) — a real team enables a starter set first and
# expands quarterly.

resource "aws_iam_role" "config" {
  name = "${local.name_prefix}-config-recorder"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "config.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config_managed" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_s3_bucket" "config_history" {
  bucket = "${local.name_prefix}-config-history-${random_id.suffix.hex}"

  tags = {
    Name    = "${local.name_prefix}-config-history"
    Purpose = "config-recorder"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config_history" {
  bucket = aws_s3_bucket.config_history.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.logs.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "config_history" {
  bucket                  = aws_s3_bucket.config_history.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_config_configuration_recorder" "main" {
  name     = "${local.name_prefix}-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "main" {
  name           = "${local.name_prefix}-channel"
  s3_bucket_name = aws_s3_bucket.config_history.id

  depends_on = [aws_config_configuration_recorder.main]
}

resource "aws_config_config_rule" "s3_bucket_server_side_encryption_enabled" {
  name = "${local.name_prefix}-s3-sse-enabled"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

resource "aws_config_config_rule" "encrypted_volumes" {
  name = "${local.name_prefix}-encrypted-volumes"

  source {
    owner             = "AWS"
    source_identifier = "ENCRYPTED_VOLUMES"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

# --- WAFv2 web ACL: in-region, attached to the app ALB ------------------
# KSI-CNA-DFP (DoS protection), KSI-SVC-ACM. Rate-limiting + the AWS
# managed common-rules + known-bad-inputs rule groups. Geo-blocking
# is tracked for a future iteration (some sponsoring-agency users
# come in via foreign relay providers, blocking-by-country produced
# false positives in the 2026-Q1 pilot).

resource "aws_wafv2_web_acl" "app" {
  name        = "${local.name_prefix}-app-waf"
  description = "Rate-limit + managed rules for the app ALB"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit-100rps"
    priority = 0

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 6000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit-100rps"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "aws-common-rule-set"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "aws-common-rule-set"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "aws-known-bad-inputs"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "aws-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-app-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "${local.name_prefix}-app-waf"
  }
}

resource "aws_wafv2_web_acl_association" "app_alb" {
  resource_arn = aws_lb.app.arn
  web_acl_arn  = aws_wafv2_web_acl.app.arn
}

# --- Federated identity: SAML provider for the corporate IdP ------------
# KSI-IAM-MFA, KSI-IAM-AAM. Operator humans federate in via the
# corporate Okta tenant; the SAML provider here is the only path the
# platform team uses for everyday console + CLI access. The legacy
# IAM users + access keys documented in DELIBERATE_GAPS are explicit
# migration debt, not the steady-state design.

resource "aws_iam_saml_provider" "okta" {
  name                   = "${local.name_prefix}-okta"
  saml_metadata_document = file("${path.module}/saml-metadata.example.xml")
}
