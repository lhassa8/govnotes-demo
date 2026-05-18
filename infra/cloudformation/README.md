# CloudFormation — Govnotes FedRAMP boundary

This is the CloudFormation representation of the same `govnotes-fedramp-prod`
boundary defined in [`../terraform/`](../terraform/). Same service, same
deliberate gaps, same expected Efterlev classifications — different
IaC tool.

## Why a parallel representation?

Two reasons:

1. **Customer parity.** Many AWS shops live in CloudFormation (often
   indirectly via SAM or CDK). Efterlev's CloudFormation scanning has
   been default-on since v0.1.99 with validated parity to the
   Terraform path (44/44 = 100% precision + 100% recall across two
   labeled fixtures). A real CFN demo proves you don't need to
   convert your IaC to use Efterlev.

2. **A/B mode.** You can scan either directory and get equivalent
   results. Delete one if you only care about the other.

## Layout

Templates are split by resource family to keep each file under ~300
lines. They're independent — you can deploy them in any order as
long as the dependency outputs are exported by predecessors.

| Template            | What it holds                                                                        |
| ------------------- | ------------------------------------------------------------------------------------ |
| `01-network.yaml`   | VPC, subnets (public/app/data), NAT, route tables, baseline security groups          |
| `02-kms.yaml`       | KMS CMKs (app data, audit logs, assets, secrets) with rotation flags                 |
| `03-storage.yaml`   | S3 buckets (user uploads, app artifacts, audit, terraform state, public-marketing)   |
| `04-data.yaml`      | RDS instances (primary, legacy), Secrets Manager secrets, DB subnet group            |
| `05-compute.yaml`   | ECS cluster, app service + task def, bastion EC2, CloudWatch log groups              |
| `06-loadbalancer.yaml` | ALB, target groups, HTTPS + HTTP + legacy listeners                               |
| `07-iam.yaml`       | Roles, groups, policies, and the legacy CI IAM user (deliberate gap)                 |
| `08-logging.yaml`   | CloudTrail, VPC flow logs                                                            |
| `09-backups.yaml`   | AWS Backup vault + plan + selection                                                  |

## Running

This is for **Efterlev scanning** primarily, not for an actual
deployment. The templates are syntactically valid and would deploy,
but the deliberate gaps documented in [`../../DELIBERATE_GAPS.md`](../../DELIBERATE_GAPS.md)
make this unsuitable for a real account.

To scan with Efterlev from the repo root:

    efterlev report run --target .

Efterlev walks the repo root and scans both `infra/terraform/` and
`infra/cloudformation/` simultaneously (it's IaC-agnostic). Expect
the gap-agent classifications to be substantively the same in both
representations — the deliberate gaps are mirrored line-for-line.

If you want to scan **only** the CFN side, you can target the
subdirectory and pass `--allow-subdir-target`, but you'll lose the
`.github/workflows/` + `.efterlev/manifests/` evidence:

    efterlev report run --target infra/cloudformation --allow-subdir-target

## Deliberate gaps

See [`../../DELIBERATE_GAPS.md`](../../DELIBERATE_GAPS.md). Each gap
catalogued there is reproduced in BOTH `infra/terraform/` and the
corresponding CloudFormation template. Cross-reference table:

| Gap                                   | Terraform location                 | CloudFormation location                   |
| ------------------------------------- | ---------------------------------- | ----------------------------------------- |
| `user_uploads` bucket without SSE     | `data.tf`, storage module          | `03-storage.yaml` UserUploadsBucket       |
| Legacy CI IAM user with access key    | `iam.tf`                           | `07-iam.yaml` LegacyCiUser                |
| ALB :80 listener without redirect     | `loadbalancer.tf`                  | `06-loadbalancer.yaml` HttpListener       |
| Secrets without rotation              | `data.tf`                          | `04-data.yaml` JwtSigningKey / DbUrl      |
| Legacy break-glass admin role        | `iam.tf`                           | `07-iam.yaml` LegacyBreakGlassAdminRole   |
| (full catalog: see DELIBERATE_GAPS.md) | various                            | various                                   |

When you add/remove a gap, update BOTH IaC representations AND the
catalog in one commit so the ground truth stays consistent across
the two paths.
