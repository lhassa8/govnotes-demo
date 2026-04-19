# ------------------------------------------------------------------------
# Shared policy fragments
# ------------------------------------------------------------------------

data "aws_iam_policy_document" "assume_role_ecs_tasks" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "assume_role_ec2" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# ------------------------------------------------------------------------
# ECS task execution role — pulls images, reads secrets, writes logs
# ------------------------------------------------------------------------

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${local.name_prefix}-ecs-task-execution"
  assume_role_policy = data.aws_iam_policy_document.assume_role_ecs_tasks.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "ecs_task_execution_extras" {
  statement {
    sid    = "ReadAppSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [
      aws_secretsmanager_secret.db_url.arn,
      aws_secretsmanager_secret.jwt_signing_key.arn
    ]
  }

  statement {
    sid    = "DecryptAppKMS"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey"
    ]
    resources = [aws_kms_key.app.arn]
  }
}

resource "aws_iam_policy" "ecs_task_execution_extras" {
  name   = "${local.name_prefix}-ecs-task-execution-extras"
  policy = data.aws_iam_policy_document.ecs_task_execution_extras.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_extras" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = aws_iam_policy.ecs_task_execution_extras.arn
}

# ------------------------------------------------------------------------
# App task role — what the running app can do at runtime
# ------------------------------------------------------------------------

resource "aws_iam_role" "app_task" {
  name               = "${local.name_prefix}-app-task"
  assume_role_policy = data.aws_iam_policy_document.assume_role_ecs_tasks.json
}

data "aws_iam_policy_document" "app_task" {
  statement {
    sid    = "ReadWriteUserUploads"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      local.user_uploads_bucket_arn,
      "${local.user_uploads_bucket_arn}/*"
    ]
  }

  statement {
    sid    = "ReadAppAssets"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      local.assets_bucket_arn,
      "${local.assets_bucket_arn}/*"
    ]
  }

  statement {
    sid       = "WriteAppLogs"
    effect    = "Allow"
    actions   = ["logs:PutLogEvents", "logs:CreateLogStream"]
    resources = ["${aws_cloudwatch_log_group.app.arn}:*"]
  }
}

resource "aws_iam_policy" "app_task" {
  name   = "${local.name_prefix}-app-task"
  policy = data.aws_iam_policy_document.app_task.json
}

resource "aws_iam_role_policy_attachment" "app_task" {
  role       = aws_iam_role.app_task.name
  policy_arn = aws_iam_policy.app_task.arn
}

# ------------------------------------------------------------------------
# Bastion instance profile
# ------------------------------------------------------------------------

resource "aws_iam_role" "bastion" {
  name               = "${local.name_prefix}-bastion"
  assume_role_policy = data.aws_iam_policy_document.assume_role_ec2.json
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${local.name_prefix}-bastion"
  role = aws_iam_role.bastion.name
}

# ------------------------------------------------------------------------
# Human IAM groups — MFA-enforced
#
# Our human operators federate in via the IdP in general; these groups
# exist for a small number of legacy break-glass accounts that haven't
# yet been migrated. Policies attached here require MFA.
# ------------------------------------------------------------------------

resource "aws_iam_group" "platform_admins" {
  name = "${local.name_prefix}-platform-admins"
}

resource "aws_iam_group" "readonly_auditors" {
  name = "${local.name_prefix}-readonly-auditors"
}

data "aws_iam_policy_document" "platform_admin" {
  statement {
    sid    = "AdminActions"
    effect = "Allow"
    actions = [
      "ec2:*",
      "ecs:*",
      "rds:*",
      "s3:*",
      "iam:Get*",
      "iam:List*",
      "kms:Describe*",
      "kms:List*"
    ]
    resources = ["*"]

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
}

resource "aws_iam_policy" "platform_admin" {
  name   = "${local.name_prefix}-platform-admin"
  policy = data.aws_iam_policy_document.platform_admin.json
}

resource "aws_iam_group_policy_attachment" "platform_admin" {
  group      = aws_iam_group.platform_admins.name
  policy_arn = aws_iam_policy.platform_admin.arn
}

# Older read-only policy used by the auditor group. Predates the
# MFA-enforcement rollout; revisit as part of the IA-2 cleanup epic.
data "aws_iam_policy_document" "readonly_auditor" {
  statement {
    sid    = "ReadOnlyAudit"
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "ecs:Describe*",
      "ecs:List*",
      "rds:Describe*",
      "s3:GetBucketLocation",
      "s3:GetBucketPolicy",
      "s3:GetBucketTagging",
      "s3:ListAllMyBuckets",
      "iam:Get*",
      "iam:List*",
      "cloudtrail:LookupEvents",
      "logs:Describe*",
      "logs:Get*",
      "logs:FilterLogEvents"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "readonly_auditor" {
  name   = "${local.name_prefix}-readonly-auditor"
  policy = data.aws_iam_policy_document.readonly_auditor.json
}

resource "aws_iam_group_policy_attachment" "readonly_auditor" {
  group      = aws_iam_group.readonly_auditors.name
  policy_arn = aws_iam_policy.readonly_auditor.arn
}

# ------------------------------------------------------------------------
# CI deploy user
#
# Used by the legacy Jenkins pipeline that still pushes Terraform plans
# for this account. Being migrated to GitHub Actions OIDC in Q2; keep
# around until that ships, then delete.
# ------------------------------------------------------------------------

resource "aws_iam_user" "ci_deploy" {
  name = "${local.name_prefix}-ci-deploy"

  tags = {
    Purpose = "ci-deploy"
    Owner   = "platform-team"
  }
}

resource "aws_iam_access_key" "ci_deploy" {
  user = aws_iam_user.ci_deploy.name
}

data "aws_iam_policy_document" "ci_deploy" {
  statement {
    sid    = "TerraformPlanApply"
    effect = "Allow"
    actions = [
      "ec2:*",
      "ecs:*",
      "rds:Describe*",
      "s3:*",
      "iam:Get*",
      "iam:List*",
      "iam:PassRole",
      "logs:Describe*",
      "cloudformation:Describe*"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ci_deploy" {
  name   = "${local.name_prefix}-ci-deploy"
  policy = data.aws_iam_policy_document.ci_deploy.json
}

resource "aws_iam_user_policy_attachment" "ci_deploy" {
  user       = aws_iam_user.ci_deploy.name
  policy_arn = aws_iam_policy.ci_deploy.arn
}
