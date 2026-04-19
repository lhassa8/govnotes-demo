# Terraform — Govnotes FedRAMP boundary

This is the Terraform for the `govnotes-fedramp-prod` AWS account.

## Layout

Flat file layout on purpose. The boundary is small enough that splitting
into per-service modules would be premature.

| File | What it holds |
|------|---------------|
| `versions.tf` | Terraform + provider version pins, S3 remote state. |
| `variables.tf` | Input variables. |
| `main.tf` | Provider config, default tags, account-wide data sources. |
| `network.tf` | VPC, subnets, route tables, NAT, security groups. |
| `compute.tf` | ECS cluster, app service, task definitions, bastion. |
| `data.tf` | KMS keys, S3 buckets, RDS instances. |
| `iam.tf` | Roles, groups, policies, and the legacy CI user. |
| `logging.tf` | CloudTrail, the audit log bucket, VPC flow logs. |
| `loadbalancer.tf` | ALB, target groups, listeners. |
| `backups.tf` | AWS Backup vault and plan. |

## Running

```
terraform init
terraform plan -var-file=prod.tfvars
terraform apply -var-file=prod.tfvars
```

Expect `terraform plan` to take 30–60 seconds because we hit a lot of
AWS APIs during the refresh.

## Remote state

S3 bucket `govnotes-fedramp-tfstate` in us-east-1, locked by the
DynamoDB table `govnotes-fedramp-tfstate-locks`. Access to the state
bucket is restricted to the platform team's federated role.

## Known TODOs

- Migrate the legacy CI user to GitHub Actions OIDC (tracked as
  PLAT-1184).
- Wire the port-80 listener to redirect rather than 404.
- Revisit the rotation story for the assets CMK once ops confirms their
  manual process.
- Move `legacy-api.gov.govnotes.com` customers to the modern listener
  and delete listener 8443 (tracked in the Q3 API-modernization epic).

## Change management

Do not run `terraform apply` against the FedRAMP account outside of an
approved change window. See the engineering wiki for the current CAB
process.
