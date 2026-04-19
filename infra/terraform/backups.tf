resource "aws_backup_vault" "main" {
  name        = "${local.name_prefix}-vault"
  kms_key_arn = aws_kms_key.app.arn

  tags = {
    Name = "${local.name_prefix}-vault"
  }
}

resource "aws_backup_plan" "main" {
  name = "${local.name_prefix}-plan"

  rule {
    rule_name         = "daily-35d"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 5 ? * * *)"
    start_window      = 60
    completion_window = 180

    lifecycle {
      delete_after = 35
    }
  }

  rule {
    rule_name         = "weekly-90d"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 6 ? * SUN *)"
    start_window      = 60
    completion_window = 360

    lifecycle {
      cold_storage_after = 30
      delete_after       = 90
    }
  }

  tags = {
    Name = "${local.name_prefix}-plan"
  }
}

resource "aws_iam_role" "backup" {
  name = "${local.name_prefix}-backup"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "backup.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_backup_selection" "app_db" {
  iam_role_arn = aws_iam_role.backup.arn
  name         = "${local.name_prefix}-app-db"
  plan_id      = aws_backup_plan.main.id

  resources = [
    aws_db_instance.app.arn
  ]
}
