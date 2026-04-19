terraform {
  required_version = ">= 1.6.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }

  backend "s3" {
    bucket         = "govnotes-staging-tfstate"
    key            = "staging/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "govnotes-staging-tfstate-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Product     = "govnotes"
      Environment = "staging"
      Boundary    = "outside-fedramp"
      Owner       = "platform-team"
      ManagedBy   = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  name_prefix = "govnotes-staging"
}

# ------------------------------------------------------------------------
# VPC
#
# Staging runs in a different AWS account from commercial and from the
# FedRAMP boundary. It is intentionally minimal — just enough for the
# engineering team to test PRs end-to-end.
# ------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = "10.80.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.80.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "${local.name_prefix}-public-a"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.80.10.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "${local.name_prefix}-private-a"
  }
}

# ------------------------------------------------------------------------
# Staging S3 bucket — used for PR-generated artifacts.
# No encryption, no versioning. Staging is not in the FedRAMP boundary
# and holds no regulated data.
# ------------------------------------------------------------------------

resource "aws_s3_bucket" "pr_artifacts" {
  bucket = "${local.name_prefix}-pr-artifacts"

  tags = {
    Name = "${local.name_prefix}-pr-artifacts"
  }
}

resource "aws_s3_bucket_public_access_block" "pr_artifacts" {
  bucket                  = aws_s3_bucket.pr_artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------------------
# Staging RDS — shared by all engineers. Data is synthetic and
# disposable.
# ------------------------------------------------------------------------

resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnets"
  subnet_ids = [aws_subnet.private_a.id]
}

resource "aws_security_group" "db" {
  name        = "${local.name_prefix}-db-sg"
  description = "Staging DB — reachable from the VPC"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }
}

resource "aws_db_instance" "app" {
  identifier             = "${local.name_prefix}-app-db"
  engine                 = "postgres"
  engine_version         = "15.6"
  instance_class         = "db.t4g.small"
  allocated_storage      = 20
  storage_type           = "gp3"
  db_name                = "govnotes_staging"
  username               = "govnotes_app"
  password               = "change-me-in-staging"
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]

  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = false
  publicly_accessible     = false
}

# ------------------------------------------------------------------------
# Staging IAM role — looser permissions so engineers can debug freely.
# ------------------------------------------------------------------------

resource "aws_iam_role" "staging_debug" {
  name = "${local.name_prefix}-debug"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "staging_debug" {
  name = "${local.name_prefix}-debug"
  role = aws_iam_role.staging_debug.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "*"
      Resource = "*"
    }]
  })
}
