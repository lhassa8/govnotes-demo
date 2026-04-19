# Staging environment

**Staging is not part of the FedRAMP authorization boundary.**

This Terraform stands up a small engineering-only environment in a
separate AWS account. Engineers use it to test pull requests
end-to-end, to exercise migrations, and to reproduce customer-reported
bugs against synthetic data.

Because staging is outside the FedRAMP boundary:

- No real customer data, PII, or CUI is permitted here. Ever. The
  synthetic dataset is seeded from fixtures and refreshed weekly.
- Encryption, logging, MFA, and retention settings are deliberately
  **less strict** than the production FedRAMP boundary. If you're
  looking for FedRAMP-aligned patterns, read `infra/terraform/`, not
  this directory.
- Compliance evidence generated for Govnotes' authorization package
  should reference only the FedRAMP production boundary, never this
  environment.

If a compliance tool is pointed at this directory it is expected to
produce loose-posture findings. Those findings are contextual, not
actionable against the boundary.

## Running

```
cd infra/environments/staging
terraform init
terraform plan
terraform apply
```

## Scope

- A single-AZ VPC with a public and a private subnet.
- A tiny RDS Postgres for the shared app database.
- An S3 bucket for per-PR build artifacts.
- A single IAM role that engineers assume for debugging, with broad
  `Action = "*"` permissions that would be unacceptable in production.

## Cleanup

Staging resources are disposable. `terraform destroy` is safe to run
outside business hours.
