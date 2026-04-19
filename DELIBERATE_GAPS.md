# Deliberate gaps in govnotes

This document is the ground-truth catalog of the compliance gaps that
exist in this repository on purpose. Govnotes is a synthetic
FedRAMP-boundary codebase used as a scanning target — the gaps are
placed here so that automated compliance tooling has known findings to
match against.

Every gap below is:

- **Realistic.** It mirrors a mistake a distracted engineering team
  would plausibly make during a real FedRAMP Moderate build-out.
- **Scoped to six control areas.** Only SC-28, SC-8, SC-13, IA-2,
  AU-2/AU-12, and CP-9 are in scope here.
- **Documented with its fix.** Each entry states what a correct
  implementation would look like.

If you are a human reader: do not use this codebase as a reference for
what good looks like. Read `docs/compliance-status.md` for what the
team _thinks_ it has implemented; compare it to the list below to see
the delta.

Line numbers are approximate — they reflect the state of the files at
the time this document was last updated and will drift if the files are
edited. Resource names are the stable anchor.

---

## 1. S3 bucket `user-uploads` lacks encryption at rest

- **File:** `infra/terraform/data.tf`, resource `aws_s3_bucket.user_uploads`
  (around line 216). There is no corresponding
  `aws_s3_bucket_server_side_encryption_configuration` resource for this
  bucket — contrast with `aws_s3_bucket_server_side_encryption_configuration.artifacts`,
  `.assets`, `.backups`, and `.cloudtrail`, which are all present.
- **Control:** SC-28 (Protection of Information at Rest).
- **Severity:** High.
- **What's wrong:** The `govnotes-fedramp-prod-user-uploads` bucket
  stores customer-supplied attachments — potentially sensitive
  content — and has no server-side encryption configured. New objects
  written to the bucket will not be encrypted.
- **Why this happens in real teams:** When the team rolled out the
  FedRAMP buckets, they added a `aws_s3_bucket_server_side_encryption_configuration`
  resource for each bucket as they went. The `user_uploads` bucket was
  defined last, in a separate section of `data.tf`, and the matching
  SSE resource was never added. The `aws_s3_bucket_public_access_block`
  was added, which gives the bucket the visual footprint of being
  hardened; the missing piece is easy to miss on a skim.
- **Fix:** Add an `aws_s3_bucket_server_side_encryption_configuration`
  resource referencing `aws_s3_bucket.user_uploads.id`, using
  `sse_algorithm = "aws:kms"` with `kms_master_key_id = aws_kms_key.app.arn`
  and `bucket_key_enabled = true`, to match the pattern used for the
  `artifacts` and `backups` buckets.

## 2. S3 bucket `user-uploads` lacks versioning

- **File:** `infra/terraform/data.tf`, resource `aws_s3_bucket.user_uploads`
  (around line 216). Same bucket as above. No matching
  `aws_s3_bucket_versioning` resource exists — contrast with the
  `artifacts`, `assets`, `backups`, and `cloudtrail` buckets, which all
  have versioning enabled.
- **Control:** CP-9 (System Backup).
- **Severity:** Medium.
- **What's wrong:** Without versioning, accidental or malicious
  overwrite or deletion of customer attachments is unrecoverable. There
  is no intra-bucket backup.
- **Why this happens in real teams:** Same root cause as the encryption
  gap — this bucket was set up in a rush and the non-security extras
  were skipped. The tagging and public-access-block landed; versioning
  did not.
- **Fix:** Add an `aws_s3_bucket_versioning` resource referencing
  `aws_s3_bucket.user_uploads.id` with `versioning_configuration.status = "Enabled"`,
  matching the pattern used for the `artifacts` and `backups` buckets.

## 3. EBS volume `bastion_scratch` has `encrypted = false`

- **File:** `infra/terraform/compute.tf`, resource
  `aws_ebs_volume.bastion_scratch`, specifically the line
  `encrypted = false` (around line 150).
- **Control:** SC-28 (Protection of Information at Rest).
- **Severity:** Medium.
- **What's wrong:** The scratch volume attached to the bastion host is
  explicitly unencrypted. When operators use it to stage pg_dump output
  during a break-glass session, that data sits on disk in plaintext.
- **Why this happens in real teams:** The bastion was provisioned
  before the FedRAMP boundary standardized on encrypted-by-default.
  When the boundary was rebuilt, the root volume was updated but this
  auxiliary scratch volume was not.
- **Fix:** Change `encrypted = false` to `encrypted = true` and add
  `kms_key_id = aws_kms_key.app.arn` so the volume uses the app CMK,
  matching the pattern used on `aws_instance.bastion.root_block_device`.

## 4. Secondary ALB listener allows TLS 1.0/1.1

- **File:** `infra/terraform/loadbalancer.tf`, resource
  `aws_lb_listener.legacy_api` (around line 83). The
  `ssl_policy = "ELBSecurityPolicy-2016-08"` setting (around line 87)
  accepts TLS 1.0 and 1.1. Contrast with `aws_lb_listener.https`, which correctly uses
  `ELBSecurityPolicy-TLS13-1-2-2021-06`.
- **Control:** SC-8 (Transmission Confidentiality and Integrity).
- **Severity:** High.
- **What's wrong:** Older government customer integrations
  (`legacy-api.gov.govnotes.com`) can negotiate deprecated TLS versions
  against the boundary. The traffic is still encrypted, but with ciphers
  and protocol versions that are not FIPS- or FedRAMP-compliant.
- **Why this happens in real teams:** The listener exists to unblock
  legacy customer clients that cannot be upgraded on govnotes' schedule.
  The team intended this as a transition hack for one or two quarters
  and tracked its removal in an epic they then deferred.
- **Fix:** Either remove `aws_lb_listener.legacy_api` entirely (preferred
  once the legacy customers cut over), or set
  `ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"` to match the
  primary listener.

## 5. ALB security group allows inbound port 80 without redirect

- **File:** `infra/terraform/network.tf`, resource
  `aws_security_group.alb`, ingress block for port 80 (around line 156).
  The paired listener in `infra/terraform/loadbalancer.tf`
  (`aws_lb_listener.http`) responds with a fixed 404 rather than a
  `redirect` action to HTTPS.
- **Control:** SC-8 (Transmission Confidentiality and Integrity).
- **Severity:** Low.
- **What's wrong:** The ALB accepts cleartext HTTP traffic and does not
  force clients to upgrade to HTTPS. Today the listener returns 404,
  but the surface is there.
- **Why this happens in real teams:** The team added the port-80
  ingress intending to wire up a redirect and shipped the fixed-404 as
  a placeholder. The TODO is visible inline in `network.tf`.
- **Fix:** Change the default action of `aws_lb_listener.http` to a
  `redirect` block (status_code `HTTP_301`, protocol `HTTPS`, port
  `443`) instead of `fixed-response`. The security group rule itself
  can stay as long as the listener redirects.

## 6. KMS key `assets` has rotation disabled

- **File:** `infra/terraform/data.tf`, resource `aws_kms_key.assets`
  (around line 39), with `enable_key_rotation = false` on line 43. Contrast
  with `aws_kms_key.app` and `aws_kms_key.logs`, which both have
  rotation enabled.
- **Control:** SC-13 (Cryptographic Protection).
- **Severity:** Low.
- **What's wrong:** The CMK used to encrypt the static-assets bucket
  is not rotated automatically. The inline comment claims rotation is
  being handled manually, but there is no corresponding runbook or
  schedule in the Terraform (nor anywhere else in this repo).
- **Why this happens in real teams:** An engineer who was unsure about
  the blast radius of automatic rotation left it disabled "temporarily"
  and never came back to it. The comment is an artifact of the
  intention rather than a current control.
- **Fix:** Set `enable_key_rotation = true` on `aws_kms_key.assets`,
  matching `aws_kms_key.app` and `aws_kms_key.logs`.

## 7. IAM policy `readonly_auditor` does not require MFA

- **File:** `infra/terraform/iam.tf`, data block
  `aws_iam_policy_document.readonly_auditor` (around line 203). The
  statement has no `condition` requiring `aws:MultiFactorAuthPresent`.
  Contrast with `aws_iam_policy_document.platform_admin`, which has
  the MFA condition.
- **Control:** IA-2 (Identification and Authentication — Organizational
  Users).
- **Severity:** Medium.
- **What's wrong:** A principal in the `readonly_auditors` group can
  exercise the read-only permissions without an MFA-authenticated
  session. FedRAMP Moderate requires MFA for all privileged and
  non-privileged access by organizational users.
- **Why this happens in real teams:** The auditor group policy
  predates the MFA-enforcement rollout. When the platform team added
  the condition to the admin policy they did not audit the other
  policies in the same pass.
- **Fix:** Add a `condition` block inside the statement requiring
  `aws:MultiFactorAuthPresent = true`, mirroring the pattern used in
  `aws_iam_policy_document.platform_admin`.

## 8. Long-lived IAM user `ci-deploy` with access keys

- **File:** `infra/terraform/iam.tf`, resources `aws_iam_user.ci_deploy`
  (around line 245) and `aws_iam_access_key.ci_deploy` (around line 254).
- **Control:** IA-2 (Identification and Authentication — Organizational
  Users).
- **Severity:** High.
- **What's wrong:** A long-lived IAM user with programmatic access keys
  exists in the FedRAMP boundary. Its policy is broad. FedRAMP Moderate
  strongly favors short-lived federated credentials (OIDC, IAM roles)
  over static IAM user access keys, and the static keys can be exposed
  or exfiltrated without detection.
- **Why this happens in real teams:** The legacy Jenkins pipeline that
  predates the GitHub Actions migration still needs AWS credentials.
  The team tracked the migration but hasn't completed it.
- **Fix:** Delete `aws_iam_user.ci_deploy`, `aws_iam_access_key.ci_deploy`,
  `aws_iam_policy.ci_deploy`, and `aws_iam_user_policy_attachment.ci_deploy`.
  Replace with an `aws_iam_role` configured for OIDC federation from
  GitHub Actions (`token.actions.githubusercontent.com`) and attach the
  same scoped policy to the role instead of the user.

## 9. CloudTrail is single-region

- **File:** `infra/terraform/logging.tf`, resource `aws_cloudtrail.main`,
  setting `is_multi_region_trail = false` (around line 107).
- **Control:** AU-2 (Event Logging), AU-12 (Audit Generation).
- **Severity:** Medium.
- **What's wrong:** CloudTrail only records events in us-east-1. Any
  API activity in other regions — even accidental activity such as an
  operator running a command in the wrong region — will not be captured
  in the audit record. FedRAMP Moderate expects complete coverage.
- **Why this happens in real teams:** The boundary runs in a single
  region today, so the team assumed a single-region trail was
  sufficient. It is not — a multi-region trail still captures
  same-region events, and catches out-of-region activity that would
  otherwise be invisible.
- **Fix:** Change `is_multi_region_trail = false` to
  `is_multi_region_trail = true`.

## 10. CloudTrail log file validation is disabled

- **File:** `infra/terraform/logging.tf`, resource `aws_cloudtrail.main`,
  setting `enable_log_file_validation = false` (around line 108).
- **Control:** AU-2 (Event Logging), AU-12 (Audit Generation).
- **Severity:** Medium.
- **What's wrong:** Without log file validation, tampering with delivered
  CloudTrail log files in the S3 bucket cannot be detected after the
  fact. The digest files that would let auditors verify integrity are
  not produced.
- **Why this happens in real teams:** The setting is off by default in
  the AWS provider when not specified; here it is explicitly set to
  false, which is an even stronger signal that someone considered it
  and did not turn it on. The team likely intended to revisit after
  the SIEM integration.
- **Fix:** Change `enable_log_file_validation = false` to
  `enable_log_file_validation = true`.

## 11. RDS `analytics-db` has backups disabled

- **File:** `infra/terraform/data.tf`, resource `aws_db_instance.analytics`,
  setting `backup_retention_period = 0` (around line 331). Contrast with
  `aws_db_instance.app`, which retains backups for 14 days.
- **Control:** CP-9 (System Backup).
- **Severity:** Medium.
- **What's wrong:** The analytics database has no automated backups
  and no point-in-time-recovery window. Even though the data is
  sourced from the primary via ETL, loss of the analytics store still
  represents a loss of audit-relevant reporting state. The boundary
  should have backups on every in-boundary datastore.
- **Why this happens in real teams:** The analytics DB was spun up
  quickly by the analytics team to unblock a dashboard. Backups were
  disabled to avoid the storage cost on what was framed as a
  "disposable" database. It has since become part of the boundary
  without the backup config being revisited.
- **Fix:** Change `backup_retention_period = 0` to `backup_retention_period = 7`
  (or higher) and flip `skip_final_snapshot = true` to `false`. Also
  add this instance to the `aws_backup_selection.app_db` resources list
  in `infra/terraform/backups.tf`.

---

## Summary table

| # | Control | File | Resource | Severity |
|---|---------|------|----------|----------|
| 1 | SC-28 | data.tf | `aws_s3_bucket.user_uploads` | High |
| 2 | CP-9  | data.tf | `aws_s3_bucket.user_uploads` | Medium |
| 3 | SC-28 | compute.tf | `aws_ebs_volume.bastion_scratch` | Medium |
| 4 | SC-8  | loadbalancer.tf | `aws_lb_listener.legacy_api` | High |
| 5 | SC-8  | network.tf, loadbalancer.tf | `aws_security_group.alb`, `aws_lb_listener.http` | Low |
| 6 | SC-13 | data.tf | `aws_kms_key.assets` | Low |
| 7 | IA-2  | iam.tf | `aws_iam_policy_document.readonly_auditor` | Medium |
| 8 | IA-2  | iam.tf | `aws_iam_user.ci_deploy` | High |
| 9 | AU-2/AU-12 | logging.tf | `aws_cloudtrail.main` | Medium |
| 10 | AU-2/AU-12 | logging.tf | `aws_cloudtrail.main` | Medium |
| 11 | CP-9  | data.tf | `aws_db_instance.analytics` | Medium |

Showcase finding for the remediation demo: gap #1
(`aws_s3_bucket.user_uploads` lacking SSE). The fix is small,
self-contained, and maps cleanly to an auto-generated patch.
