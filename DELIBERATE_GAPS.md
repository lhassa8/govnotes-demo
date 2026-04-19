# Deliberate gaps in govnotes

This document is the ground-truth catalog of the compliance gaps that
exist in this repository on purpose. Govnotes is a synthetic FedRAMP
20x boundary codebase used as a scanning target — the gaps are placed
here so automated compliance tooling has known findings to match
against.

Every gap below is:

- **Realistic.** It mirrors a mistake a distracted engineering team
  would plausibly make during a real FedRAMP 20x build-out.
- **Scoped.** Only the production boundary (`infra/terraform/`) is
  ground-truthed here. The `infra/environments/staging/` environment
  is intentionally looser and is out of scope for this document — see
  its own README.
- **Classified.** Each gap is labeled `not implemented` or
  `partially implemented`, matching the language we want the Gap
  Agent to produce.
- **Documented with a fix.** Each entry says what a correct
  implementation would look like, so the Remediation Agent has a
  reference point.

Line numbers are approximate — they reflect file state at the time of
writing and will drift with edits. Resource names are the stable
anchor. Detector ids use a capability shape (`aws.<capability>`) that
maps to the Efterlev detector responsible for the finding.

---

## Binary gaps — "not implemented"

### 1. S3 bucket `user_uploads` lacks encryption at rest

- **File:** `infra/terraform/data.tf`, module `"storage"` entry
  `user_uploads` (around line 179). The map entry declares the bucket
  with only a `purpose` field; no `kms_key_arn` and no `sse_s3 = true`.
  The storage module at `infra/terraform/modules/storage/main.tf` gates
  the `aws_s3_bucket_server_side_encryption_configuration` resource on
  either of those fields being set (see the `if v.kms_key_arn != null
  || v.sse_s3` guard around line 43 of the module), so this bucket
  gets no SSE resource at all.
- **KSI:** KSI-SVC-VRI (Validating Resource Integrity).
- **800-53 controls:** SC-28.
- **Classification:** Not implemented.
- **What's present:** The bucket is created through the shared
  storage module, is tagged, and has `aws_s3_bucket_public_access_block`
  applied.
- **What's missing:** No server-side encryption configuration. New
  objects written to the bucket are stored unencrypted.
- **Why this happens in real teams:** Four of the five buckets in the
  storage map set `kms_key_arn` or `sse_s3` explicitly. The
  `user_uploads` entry was added during the initial FedRAMP setup and
  the author forgot to set either. The module defaults to off; nothing
  in the config draws attention to the omission.
- **Fix:** Add `kms_key_arn = aws_kms_key.app.arn` to the
  `user_uploads` entry in the `buckets` map. That single edit opts the
  bucket into the module's SSE resource.
- **Efterlev detector:** `aws.encryption_s3_at_rest`.

> This is the showcase finding for the Remediation Agent demo.

### 2. S3 bucket `user_uploads` lacks versioning

- **File:** `infra/terraform/data.tf`, same module entry as above
  (around line 179). No `versioning = true` set on the entry. The
  storage module at `modules/storage/main.tf` gates
  `aws_s3_bucket_versioning` on that flag (see around line 60).
- **KSI:** KSI-RPL-ABO (Recovery — Backups).
- **800-53 controls:** CP-9.
- **Classification:** Not implemented.
- **What's present:** Nothing relevant — the bucket exists but has no
  versioning configuration.
- **What's missing:** An `aws_s3_bucket_versioning` resource for this
  bucket. Accidental or malicious overwrite or deletion of customer
  attachments is unrecoverable.
- **Why this happens in real teams:** Same root cause as gap #1 —
  the `user_uploads` map entry was created minimally and neither opt-in
  flag was set. Bad hygiene clusters on the same resource.
- **Fix:** Add `versioning = true` to the `user_uploads` entry. Turns
  on the module's versioning resource for this bucket.
- **Efterlev detector:** `aws.backup_s3_versioning`.

### 3. EBS volume `bastion_scratch` has `encrypted = false`

- **File:** `infra/terraform/compute.tf`, resource
  `aws_ebs_volume.bastion_scratch` (around line 146). The
  `encrypted = false` line sits at line 150.
- **KSI:** KSI-SVC-VRI.
- **800-53 controls:** SC-28.
- **Classification:** Not implemented.
- **What's present:** The volume exists and is attached via
  `aws_volume_attachment.bastion_scratch`.
- **What's missing:** Encryption. The bastion's root volume (on
  `aws_instance.bastion`) is encrypted with the app CMK; this scratch
  volume is explicitly not.
- **Why this happens in real teams:** The bastion was rebuilt on
  AL2023 with encrypted storage. The scratch data volume is a leftover
  from the pre-rebuild jumphost and never had its encryption flipped
  on — the CHANGELOG calls this out as a TBD.
- **Fix:** Change `encrypted = false` to `encrypted = true` and add
  `kms_key_id = aws_kms_key.app.arn`, matching the root-block-device
  config on `aws_instance.bastion`.
- **Efterlev detector:** `aws.encryption_ebs`.

### 4. Secondary ALB listener allows TLS 1.0/1.1

- **File:** `infra/terraform/loadbalancer.tf`, resource
  `aws_lb_listener.legacy_api` (around line 83). The
  `ssl_policy = "ELBSecurityPolicy-2016-08"` line sits at line 87.
  Contrast with `aws_lb_listener.https` (around line 43), which uses
  `ELBSecurityPolicy-TLS13-1-2-2021-06`.
- **KSI:** KSI-SVC-SNT (Securing Network Traffic).
- **800-53 controls:** SC-8, SC-13.
- **Classification:** Not implemented.
- **What's present:** The primary customer listener negotiates
  TLS 1.2+ with a modern policy.
- **What's missing:** The secondary listener on port 8443 negotiates
  down to TLS 1.0/1.1 using a deprecated cipher policy.
- **Why this happens in real teams:** The listener exists to keep
  older government-customer integrations working during migration to
  the modern listener. The team intended this as a short-term
  transition and tracked its removal in an epic that was then deferred.
- **Fix:** Either remove `aws_lb_listener.legacy_api` (preferred once
  the legacy customers cut over), or change `ssl_policy` to
  `"ELBSecurityPolicy-TLS13-1-2-2021-06"`.
- **Efterlev detector:** `aws.tls_alb_listener`.

### 5. ALB accepts port 80 without redirect to 443

- **File:** `infra/terraform/network.tf`, resource
  `aws_security_group.alb` (around line 138); port-80 ingress block
  starts at line 154 with `from_port = 80` on line 156. Paired with
  `aws_lb_listener.http` in `infra/terraform/loadbalancer.tf` (around
  line 58), whose default action is a `fixed-response` returning a 404
  rather than a `redirect` to HTTPS.
- **KSI:** KSI-SVC-SNT.
- **800-53 controls:** SC-8.
- **Classification:** Not implemented.
- **What's present:** HTTP traffic is not forwarded to the app
  service; it returns 404.
- **What's missing:** A 301 redirect upgrading clients to HTTPS. The
  ALB advertises an insecure port and doesn't coerce clients to the
  secure listener.
- **Why this happens in real teams:** The team added the port-80
  ingress intending to wire up a redirect and shipped the fixed-404
  as a placeholder. The inline TODO is still there.
- **Fix:** Change the default action of `aws_lb_listener.http` from
  `fixed-response` to a `redirect` block (status_code `HTTP_301`,
  protocol `HTTPS`, port `443`). The security group rule itself can
  remain once the listener redirects.
- **Efterlev detector:** `aws.alb_http_redirect`.

### 6. KMS key `assets` has rotation disabled

- **File:** `infra/terraform/data.tf`, resource `aws_kms_key.assets`
  (around line 39). `enable_key_rotation = false` sits at line 43.
  Contrast with `aws_kms_key.app` (line 5) and `aws_kms_key.logs`
  (line 20), which both have rotation enabled.
- **KSI:** KSI-SVC-VRI.
- **800-53 controls:** SC-12, SC-13.
- **Classification:** Not implemented.
- **What's present:** The CMK exists with a symmetric spec and a
  30-day deletion window.
- **What's missing:** Automatic key rotation. The inline comment
  claims rotation is being handled manually, but no runbook or
  schedule exists for it in the repo.
- **Why this happens in real teams:** The engineer was unsure about
  the blast radius of automatic rotation on the assets bucket and
  left it disabled "temporarily." The CHANGELOG acknowledges this.
- **Fix:** Set `enable_key_rotation = true` on `aws_kms_key.assets`,
  matching `app` and `logs`.
- **Efterlev detector:** `aws.kms_key_rotation`.

### 7. IAM policy `readonly_auditor` does not require MFA

- **File:** `infra/terraform/iam.tf`, data block
  `aws_iam_policy_document.readonly_auditor` (around line 203). The
  statement has no `condition` requiring
  `aws:MultiFactorAuthPresent`. Contrast with
  `aws_iam_policy_document.platform_admin` (around line 167), which
  does.
- **KSI:** KSI-IAM-MFA (Phishing-Resistant MFA).
- **800-53 controls:** IA-2(1), IA-2(2).
- **Classification:** Not implemented.
- **What's present:** The policy is scoped read-only.
- **What's missing:** A `condition` requiring an MFA-authenticated
  session. A principal in the `readonly_auditors` group can exercise
  the permissions without MFA.
- **Why this happens in real teams:** The policy predates the
  MFA-enforcement rollout. When the platform team added the MFA
  condition to the admin policy, they didn't audit the other policies
  in the same pass.
- **Fix:** Add a `condition` block inside the statement requiring
  `aws:MultiFactorAuthPresent = true`, mirroring
  `platform_admin`.
- **Efterlev detector:** `aws.iam_mfa_enforcement`.

### 8. Long-lived IAM user `ci_deploy` with access keys

- **File:** `infra/terraform/iam.tf`, resources
  `aws_iam_user.ci_deploy` (around line 313),
  `aws_iam_access_key.ci_deploy` (around line 322), and
  `aws_iam_policy.ci_deploy` (around line 345).
- **KSI:** KSI-IAM-MFA.
- **800-53 controls:** IA-2, AC-2.
- **Classification:** Not implemented.
- **What's present:** The user exists and is attached to a broad
  policy for Terraform plan/apply operations.
- **What's missing:** A federated-identity alternative. A long-lived
  IAM user with programmatic access keys should not exist in a
  FedRAMP boundary.
- **Why this happens in real teams:** The legacy Jenkins pipeline
  predates the GitHub Actions OIDC migration. The team tracked the
  migration (`PLAT-1184`) but has not completed it.
- **Fix:** Delete `aws_iam_user.ci_deploy`,
  `aws_iam_access_key.ci_deploy`, `aws_iam_policy.ci_deploy`, and
  `aws_iam_user_policy_attachment.ci_deploy`. Replace with an
  `aws_iam_role` that federates from GitHub Actions OIDC
  (`token.actions.githubusercontent.com`) and attach the same
  narrowed policy to the role.
- **Efterlev detector:** `aws.iam_user_access_keys`.

### 9. RDS `analytics-db` has near-zero backup retention

- **File:** `infra/terraform/data.tf`, resource
  `aws_db_instance.analytics` (around line 281). The
  `backup_retention_period = 1` line sits at line 301. Contrast with
  `aws_db_instance.app`, which retains for 30 days.
- **KSI:** KSI-RPL (Recovery Planning).
- **800-53 controls:** CP-9, CP-10.
- **Classification:** Not implemented.
- **What's present:** Automated backups are technically on —
  retention is set to a non-zero value.
- **What's missing:** Meaningful retention. A one-day window is well
  below any reasonable FedRAMP Moderate expectation and below what
  the AWS Backup plan applies to the primary DB.
- **Why this happens in real teams:** The analytics DB was spun up
  quickly by the analytics team. The retention was set to the
  minimum-non-zero to keep storage costs down under the assumption
  that the ETL source could always be re-run. That rationale doesn't
  survive FedRAMP scrutiny.
- **Fix:** Change `backup_retention_period = 1` to at least `14` (or
  `30` to match the primary). Flip `skip_final_snapshot = true` to
  `false`, and add this instance to the resources list in
  `aws_backup_selection.app_db` in `backups.tf`.
- **Efterlev detector:** `aws.backup_rds_retention`.

---

## Ambiguous cases — "partially implemented"

These are the cases where evidence is mixed. The detector should
surface both the present and absent aspects; the Gap Agent classifies
based on that evidence.

### 10. KMS key `reports` is encrypted with an overly permissive policy

- **File:** `infra/terraform/data.tf`, resource `aws_kms_key.reports`
  (around line 58), policy sourced from
  `data.aws_iam_policy_document.kms_reports` (around line 107). The
  `AllowAccountUse` statement uses `Principal { identifiers = ["*"] }`
  (around line 129) scoped by a `kms:CallerAccount` condition.
- **KSI:** KSI-SVC-VRI.
- **800-53 controls:** SC-12, SC-13.
- **Classification:** Partially implemented.
- **What's present:** Encryption at rest is configured. The CMK is
  a customer-managed symmetric key. Rotation is enabled
  (`enable_key_rotation = true`). The `internal_reports` S3 bucket is
  configured with `aws:kms` using this key (via the storage module's
  map entry in `data.tf` around line 182).
- **What's missing:** Least-privilege access to the key. The policy
  grants `Encrypt`, `Decrypt`, `ReEncrypt*`, `GenerateDataKey*`, and
  `DescribeKey` to any principal in the account. Any compromised
  identity in the account that can reach KMS can decrypt the reports
  bucket's objects. Encryption is technically present; whether it
  meaningfully protects data is debatable.
- **Why this happens in real teams:** The finance-analytics team's
  workflow cuts across several principals, and the platform team
  loosened the key policy to unblock them while the per-service role
  model was being designed. The comment on the statement says as
  much. The TBD never came back.
- **Fix:** Replace the `AllowAccountUse` statement's wildcard
  principal with the specific roles that need key access — at
  minimum, `aws_iam_role.app_task`, `aws_iam_role.data_ops`, and the
  analytics ETL role once defined. Remove the `Encrypt` action from
  any role that only reads.
- **Efterlev detector:** `aws.kms_key_policy`.

### 11. IAM role `data_ops` enforces MFA only on destructive actions

- **File:** `infra/terraform/iam.tf`, resource
  `aws_iam_role.data_ops` (around line 247) and data block
  `aws_iam_policy_document.data_ops` (around line 262). The
  `DataOpsReadWrite` statement has no MFA condition; the
  `DataOpsDestructiveRequiresMfa` statement (around line 276) does.
- **KSI:** KSI-IAM-MFA.
- **800-53 controls:** IA-2(1), IA-2(2).
- **Classification:** Partially implemented.
- **What's present:** MFA is required for delete operations
  (`s3:DeleteObject`, `s3:DeleteBucket`, `rds:DeleteDBInstance`,
  `rds:DeleteDBSnapshot`). The role is scoped rather than
  account-wide admin.
- **What's missing:** MFA enforcement on reads and writes. A
  principal assuming `data_ops` without an MFA-authenticated session
  can `GetObject`, `PutObject`, `ListBucket`, and `rds:Describe*`
  freely. FedRAMP expects MFA for privileged and non-privileged
  access to the boundary, not just for destructive calls.
- **Why this happens in real teams:** The data team scripts backfills
  from their workstations and finds MFA prompts disruptive on every
  invocation. The platform team compromised by requiring MFA only on
  the destructive side. The comment on the role spells out the
  compromise and says "revisit once federation rollout lands."
- **Fix:** Add the `aws:MultiFactorAuthPresent` condition to the
  `DataOpsReadWrite` statement too, or migrate the role to the
  federated identity flow where MFA is enforced at the identity
  provider.
- **Efterlev detector:** `aws.iam_mfa_enforcement`.

### 12. CloudTrail is multi-region but missing validation and data events

- **File:** `infra/terraform/logging.tf`, resource
  `aws_cloudtrail.main` (around line 103). `is_multi_region_trail = true`
  sits at line 108; `enable_log_file_validation = false` sits at
  line 109. The `event_selector` block (around line 113) covers
  management events only — no data-event selectors for S3 or Lambda.
- **KSI:** KSI-MLA (Monitoring, Logging, Auditing).
- **800-53 controls:** AU-2, AU-6, AU-12.
- **Classification:** Partially implemented.
- **What's present:** A trail exists. It is multi-region, so API
  activity across all regions is captured. Management events are
  included. Logs are delivered to an encrypted, versioned, restricted
  S3 bucket. The trail uses a CMK (`aws_kms_key.logs`) with rotation
  enabled. Global service events are included.
- **What's missing:**
  - Log-file integrity validation. Without it, tampering with
    delivered log files in S3 cannot be detected after the fact; no
    digest files are produced.
  - Data events for S3 and Lambda. Object-level reads/writes on
    in-boundary S3 buckets (including `user_uploads` and the
    CloudTrail bucket itself) are not captured in the audit record.
- **Why this happens in real teams:** The team stood the trail up as
  single-region, later flipped it to multi-region as part of the 20x
  readiness pass, and deferred log-file validation to the SIEM
  integration and data events to the Q2 cost review. The CHANGELOG
  and the inline comment both say so.
- **Fix:** Set `enable_log_file_validation = true`. Add a second
  `event_selector` block with `read_write_type = "All"`,
  `include_management_events = false`, and
  `data_resource` entries for `AWS::S3::Object` covering the S3
  buckets in the boundary (or a catch-all `arn:aws:s3`).
- **Efterlev detectors:** `aws.cloudtrail_coverage`,
  `aws.cloudtrail_integrity`.

---

## Summary table

| #  | KSI | Classification | File | Resource | Severity |
|----|-----|----------------|------|----------|----------|
| 1  | KSI-SVC-VRI | Not implemented | data.tf | `module.storage` entry `user_uploads` | High |
| 2  | KSI-RPL-ABO | Not implemented | data.tf | `module.storage` entry `user_uploads` | Medium |
| 3  | KSI-SVC-VRI | Not implemented | compute.tf | `aws_ebs_volume.bastion_scratch` | Medium |
| 4  | KSI-SVC-SNT | Not implemented | loadbalancer.tf | `aws_lb_listener.legacy_api` | High |
| 5  | KSI-SVC-SNT | Not implemented | network.tf, loadbalancer.tf | `aws_security_group.alb`, `aws_lb_listener.http` | Low |
| 6  | KSI-SVC-VRI | Not implemented | data.tf | `aws_kms_key.assets` | Low |
| 7  | KSI-IAM-MFA | Not implemented | iam.tf | `aws_iam_policy_document.readonly_auditor` | Medium |
| 8  | KSI-IAM-MFA | Not implemented | iam.tf | `aws_iam_user.ci_deploy` | High |
| 9  | KSI-RPL     | Not implemented | data.tf | `aws_db_instance.analytics` | Medium |
| 10 | KSI-SVC-VRI | Partially implemented | data.tf | `aws_kms_key.reports` + `kms_reports` doc | Medium |
| 11 | KSI-IAM-MFA | Partially implemented | iam.tf | `aws_iam_role.data_ops` + policy doc | Medium |
| 12 | KSI-MLA     | Partially implemented | logging.tf | `aws_cloudtrail.main` | Medium |

Showcase finding for the remediation demo: gap #1 (`user_uploads`
missing encryption). The fix is a one-line addition to the storage
module's map entry, which reads cleanly as an auto-generated patch
and maps directly to the `aws.encryption_s3_at_rest` detector.

## Out of scope for this document

- `infra/environments/staging/` — intentionally looser; staging is
  not in the FedRAMP authorization boundary and has its own rules.
  Do not treat findings there as ground-truth gaps.
- Any resources created by the storage module for buckets other than
  `user_uploads` — those opt into encryption and versioning via the
  map and are expected to pass detection.
