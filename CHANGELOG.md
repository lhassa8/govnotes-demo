# Changelog — Govnotes FedRAMP boundary

This is a running log of meaningful changes to the FedRAMP-boundary
repository. Entries are written in the voice of the platform team and
are a mix of shipped work, in-flight work, and known follow-ups.

This file is for humans. It is not a substitute for the git history and
it is not the system of record for compliance evidence — see
`DELIBERATE_GAPS.md` for the ground-truth state of known gaps and
`docs/compliance-status.md` for the team's self-assessment.

---

## 2026-04

- **2026-04-10** — Promoted the staging environment out of the main
  Terraform root and into `infra/environments/staging/`. Staging is
  explicitly not in the FedRAMP authorization boundary; see the staging
  README for the rationale.
- **2026-04-04** — Extracted S3 + RDS into `modules/storage/` so we can
  iterate over bucket configurations with `for_each`. Cuts duplication
  across the artifacts / assets / backups / user-uploads buckets.
- **2026-04-02** — Added `aws_kms_key.reports` and the
  `internal-reports` S3 bucket used by the finance analytics workflow.
  Opening up the key policy slightly to unblock the analytics team's
  cross-service reads; revisit once we have the per-service roles
  defined. (TBD — KSI-SVC-VRI.)

## 2026-03

- **2026-03-20** — Wired the `data_ops` IAM role for the data team's
  EC2 workstations. MFA is required for destructive actions (Delete*,
  Terminate*); read and write paths are permitted without MFA so the
  team can script from their workstations. Revisit the scope once the
  federation rollout lands. (TBD — KSI-IAM-MFA.)
- **2026-03-14** — Turned on CloudTrail across all regions. Data events
  for S3 and Lambda are deferred to the Q2 cost-review cycle; log-file
  validation is still off pending the SIEM pipeline work. (TBD —
  KSI-MLA.)
- **2026-03-07** — Enabled MFA on the primary admin IAM policies
  (`platform_admin`). Secondary policies (`readonly_auditor`, legacy
  service accounts) are tracked for a follow-up pass. (TBD — KSI-IAM-MFA.)
- **2026-03-02** — Migrated production data to encrypted RDS with
  multi-AZ and 14-day backup retention. Secondary analytics DB is on a
  shorter retention window for cost reasons.

## 2026-02

- **2026-02-24** — Added `aws_lb_listener.legacy_api` on port 8443 to
  keep the older government-customer integrations working while we plan
  their migration to the modern listener. Intentionally TLS 1.0+
  compatible; tracked for removal in the Q3 API-modernization epic.
  (TBD — KSI-SVC-SNT.)
- **2026-02-18** — Standardized S3 bucket names across the boundary
  (`govnotes-fedramp-prod-*`) and tagged them with the `Purpose` tag.
- **2026-02-10** — Introduced the `ci-deploy` IAM user with programmatic
  access keys to unblock the Jenkins pipeline while we wait on the
  GitHub Actions OIDC migration. (TBD — KSI-IAM-MFA; PLAT-1184.)
- **2026-02-02** — Stood up `govnotes-fedramp-prod` KMS keys (`app`,
  `logs`) with automatic rotation. Assets key (`assets`) is on manual
  rotation for now while we confirm the ops procedure with the on-call
  team. (TBD — KSI-SVC-VRI.)

## 2026-01

- **2026-01-28** — Rebuilt the bastion host on Amazon Linux 2023 with
  SSM-only access. Root volume is encrypted; the scratch volume is a
  leftover from the pre-rebuild jumphost and still needs its encryption
  flipped on during a maintenance window. (TBD — KSI-SVC-VRI.)
- **2026-01-14** — VPC topology finalized: three AZs, public/private-app/
  private-data subnets, NAT per AZ.

## 2025-12

- **2025-12-18** — Customer-facing ALB listener on 443 with
  `ELBSecurityPolicy-TLS13-1-2-2021-06`. Port-80 listener returns a
  fixed 404 for now; promoting to a 301 redirect is tracked inline.
  (TBD — KSI-SVC-SNT.)
- **2025-12-02** — First pass of IAM groups (`platform_admins`,
  `readonly_auditors`). Admin policy carries the MFA condition.

## 2025-11

- **2025-11-14** — Created the FedRAMP AWS account
  (`govnotes-fedramp-prod`) and seeded the Terraform state bucket
  `govnotes-fedramp-tfstate` with DynamoDB locking.
- **2025-11-04** — Started reviewing the FedRAMP 20x Key Security
  Indicators (KSIs) guidance and mapping our existing commercial
  architecture against it. Decision: stand up a fresh boundary rather
  than retrofit.
