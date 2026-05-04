# ------------------------------------------------------------------------
# Dev sandbox — OUT OF FedRAMP boundary
#
# This Terraform root holds dev-team experimentation resources that
# explicitly do NOT live inside the production FedRAMP authorization
# boundary. The boundary is declared in `.efterlev/config.toml` (applied
# in CI by the `efterlev-scan` workflow):
#
#   [boundary]
#   include = ["infra/terraform/**"]
#   exclude = ["infra/terraform/dev_sandbox/**"]
#
# Findings against resources in this directory should be classified
# as `out_of_boundary` by the Gap Agent and DROPPED from the POA&M.
# This is the textbook FedRAMP boundary-scoping case: the resource
# exists in the same repo and AWS account, but is structurally
# excluded from the authorization package.
#
# In a real engagement this would live in a separate AWS account.
# Keeping it in-repo here is a deliberate test fixture for Efterlev's
# boundary-state detection (introduced v0.1.4).
# ------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# A dev-team scratch RDS instance. Deliberately mis-configured against
# every production-side standard: no encryption, no multi-AZ, password
# in plain text, single-AZ, no backups. This is exactly what an
# out_of_boundary finding looks like — the scanner should see all the
# gaps, but the boundary filter keeps them out of the POA&M.

resource "aws_db_instance" "dev_scratch" {
  identifier     = "govnotes-dev-scratch"
  engine         = "postgres"
  engine_version = "15.6"
  instance_class = "db.t4g.micro"

  allocated_storage = 20
  storage_type      = "gp2"
  storage_encrypted = false

  db_name  = "scratch"
  username = "dev"
  # Hardcoded password in source. NOT a real credential — see
  # DELIBERATE_GAPS.md "dev sandbox" entry. Detector will surface
  # this; boundary filter will drop it from the POA&M.
  password = "dev-scratch-only-not-real"
  port     = 5432

  multi_az            = false
  publicly_accessible = false
  skip_final_snapshot = true

  backup_retention_period = 0

  tags = {
    Name        = "govnotes-dev-scratch"
    Environment = "dev"
    Boundary    = "excluded"
  }
}

# Likewise: a dev S3 bucket with no encryption. Real "we'll fix it
# eventually" pattern; the boundary scoping says "we don't have to,
# this isn't in the FedRAMP package."

resource "aws_s3_bucket" "dev_scratch" {
  bucket = "govnotes-dev-scratch-bucket"

  tags = {
    Name     = "govnotes-dev-scratch"
    Boundary = "excluded"
  }
}
