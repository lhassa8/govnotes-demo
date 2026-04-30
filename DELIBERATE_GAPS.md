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

## Coverage gaps — capability surfaces not yet built out

The gaps above are misconfigurations on resources that exist. The gaps
below are entire capability surfaces a FedRAMP 20x customer is expected
to implement that this codebase does not yet declare. They surface as
"not implemented" findings because the corresponding evidence is absent
at the IaC layer.

### 13. EC2 bastion allows IMDSv1 (no `http_tokens = "required"`)

- **File:** `infra/terraform/compute.tf`, resource
  `aws_instance.bastion` (around line 123). No `metadata_options` block.
  The default behavior on `aws_instance` without an explicit
  `metadata_options` block is IMDSv1 + IMDSv2 both accepted.
- **KSI:** KSI-CNA-IBP (Immutable Build Pipeline / Image-Based Posture).
  Cross-mapped to KSI-CNA-DFP via CM-2.
- **800-53 controls:** CM-2, CM-6.
- **Classification:** Not implemented.
- **What's present:** The bastion is encrypted at rest, in a private
  subnet, monitored, and SSM-only.
- **What's missing:** Enforced IMDSv2. A workload that gets SSRF'd to
  `http://169.254.169.254/latest/meta-data/` on this instance can
  exfiltrate the role's STS token via IMDSv1.
- **Why this happens in real teams:** Default Terraform behavior; the
  team didn't know IMDSv1 needed to be explicitly disabled. The Capital
  One breach made `http_tokens = "required"` the canonical safe default,
  but Terraform still defaults to optional.
- **Fix:** Add a `metadata_options` block to `aws_instance.bastion`
  with `http_tokens = "required"` and `http_endpoint = "enabled"`.
- **Efterlev detector:** `aws.ec2_imdsv2_required`.

### 14. NACLs default-permissive (no `aws_network_acl` declared)

- **File:** `infra/terraform/network.tf`. No `aws_network_acl` or
  `aws_network_acl_rule` resources are declared, so the VPC's
  subnets fall back to the default network ACL — which allows all
  inbound and outbound IPv4/IPv6 traffic.
- **KSI:** KSI-CNA-RNT (Restricting Network Traffic).
- **800-53 controls:** SC-7, SC-7(5).
- **Classification:** Not implemented.
- **What's present:** Per-subnet routing is set up; security groups
  enforce allow-list ingress at the instance/ENI layer.
- **What's missing:** Subnet-level deny-list traffic restriction.
  Defense-in-depth between security groups and the wire is absent;
  any SG misconfig that allows broader-than-intended traffic is not
  countered at the NACL layer.
- **Why this happens in real teams:** Teams that come from VPC-defaults
  often treat security groups as sufficient. NACLs are a separate
  mental model and are more often added during a 3PAO finding than
  during initial buildout.
- **Fix:** Declare per-tier `aws_network_acl` resources for `public`,
  `private_app`, and `private_data` subnet groups, with explicit
  ingress/egress rule allow-listing. The data tier should deny inbound
  from the public tier directly (force traffic through the app tier).
- **Efterlev detector:** `aws.nacl_restrictiveness`.

### 15. No SAML / OIDC federated identity provider

- **File:** `infra/terraform/iam.tf`. No
  `aws_iam_openid_connect_provider` or `aws_iam_saml_provider`
  resources are declared.
- **KSI:** KSI-IAM-APM (Authentication Provider Management).
- **800-53 controls:** IA-2, IA-5(2).
- **Classification:** Not implemented.
- **What's present:** Long-lived IAM users (`ci_deploy`, gap #8) and
  IAM roles assumable from within the account; MFA enforcement on
  some policies (gaps #7, #11).
- **What's missing:** A federated entry point. There's no OIDC
  provider for GitHub Actions (the migration target named in gap #8),
  no SAML provider for SSO, and no IAM Identity Center setup. Every
  human/CI principal authenticates with long-lived AWS credentials.
- **Why this happens in real teams:** The OIDC migration named in
  gap #8 (`PLAT-1184`) hasn't started. The platform team scoped it
  for after the 20x readiness sweep.
- **Fix:** Declare an `aws_iam_openid_connect_provider` for
  `token.actions.githubusercontent.com` (the GitHub Actions OIDC
  issuer). Replace `aws_iam_user.ci_deploy` (gap #8) with an
  `aws_iam_role` whose trust policy federates from that provider.
- **Efterlev detector:** `aws.federated_identity_providers`.

### 16. No S3 lifecycle policies on any bucket

- **File:** `infra/terraform/modules/storage/main.tf` and
  `infra/terraform/data.tf`. No `aws_s3_bucket_lifecycle_configuration`
  resources are declared, in the storage module or anywhere else.
- **KSI:** KSI-SVC-RUD (Removing Unwanted Data) — partial cross-mapping.
- **800-53 controls:** SI-12, SI-12(3).
- **Classification:** Not implemented.
- **What's present:** Encryption, versioning (on most buckets), and
  public-access blocks on every bucket.
- **What's missing:** Any rule that expires or transitions objects.
  The `cloudtrail` bucket grows unbounded; the `internal_reports`
  bucket has no archive cadence; `user_uploads` has no
  retention/deletion schedule. FedRAMP 20x SI-12 expects declared
  retention discipline.
- **Why this happens in real teams:** Lifecycle rules are an
  afterthought. The team intended to add them after observing real
  storage-growth patterns; "make it work first."
- **Fix:** Add `aws_s3_bucket_lifecycle_configuration` per bucket
  with at least one rule containing an `expiration` block. CloudTrail
  archive bucket: 365-day retention then expiration. user_uploads:
  defer to legal — but at least transition to STANDARD_IA after 90.
- **Efterlev detector:** `aws.s3_lifecycle_policies`.

### 17. No GuardDuty detector

- **File:** None. No `aws_guardduty_detector` resource exists in this
  codebase.
- **KSI:** KSI-MLA-OSM (Operating SIEM Capability).
- **800-53 controls:** SI-4, RA-5(11).
- **Classification:** Not implemented.
- **What's present:** CloudTrail capture, VPC Flow Logs, CloudWatch
  log groups, app-side log routing.
- **What's missing:** Threat-detection findings on the captured
  telemetry. CloudTrail collects events; nothing in the codebase
  analyzes them for compromise indicators (credential exfil, unusual
  API patterns, Tor exit-node usage, etc.).
- **Why this happens in real teams:** Cost. GuardDuty was deferred
  pending the security-budget approval that's tracked for Q2.
- **Fix:** Add `aws_guardduty_detector` with `enable = true` in this
  region. Add a corresponding `aws_guardduty_filter` /
  `aws_guardduty_publishing_destination` for the security-bucket SIEM
  pipeline once that exists (gap #21).
- **Efterlev detector:** `aws.guardduty_enabled`.

### 18. No AWS Config recording

- **File:** None. No `aws_config_configuration_recorder` or
  `aws_config_delivery_channel` resource exists.
- **KSI:** KSI-MLA-EVC (Evaluating Configurations).
  Cross-mapped to KSI-SVC-ACM (Automating Configuration Management).
- **800-53 controls:** CM-2, CM-8(2).
- **Classification:** Not implemented.
- **What's present:** Terraform itself is the declared source of truth
  (`aws.terraform_inventory` evidences this).
- **What's missing:** Continuous runtime evaluation of declared-vs-
  actual configuration. AWS Config detects drift between IaC declaration
  and runtime state. Without it, a console-introduced change is
  invisible until the next `terraform plan`.
- **Why this happens in real teams:** Same as GuardDuty (gap #17) —
  cost + assumption that "we don't change things in the console."
  Audit findings frequently reveal otherwise.
- **Fix:** Declare `aws_config_configuration_recorder` with
  `recording_group { all_supported = true, include_global_resource_types = true }`,
  paired with `aws_config_delivery_channel` writing to a Config-
  dedicated S3 bucket (encrypted, versioned, log-bucket pattern).
- **Efterlev detector:** `aws.config_enabled`.

### 19. No backup-restore testing

- **File:** `infra/terraform/backups.tf`. The file declares
  `aws_backup_plan.app_db` and `aws_backup_selection.app_db` (so
  backups happen) but no `aws_backup_restore_testing_plan` or
  `aws_backup_restore_testing_selection`.
- **KSI:** KSI-RPL-TRC (Testing Recovery Capabilities).
- **800-53 controls:** CP-4, CP-4(1).
- **Classification:** Not implemented.
- **What's present:** Daily backups of the primary RDS instance with
  appropriate retention.
- **What's missing:** Scheduled automated restore tests. AWS Backup
  Restore Testing (introduced 2023) is the cloud-native primitive for
  proving recovery actually works. Backups exist, but nothing in this
  codebase exercises them on a schedule.
- **Why this happens in real teams:** Restore-testing is a relatively
  new AWS Backup feature; many teams shipped backups before it landed
  and haven't retrofitted. CP-4 is the FedRAMP 20x line that turns
  this from a nice-to-have into an explicit requirement.
- **Fix:** Add an `aws_backup_restore_testing_plan` with a weekly
  `schedule_expression` and a paired
  `aws_backup_restore_testing_selection` referencing the existing
  app_db backup vault.
- **Efterlev detector:** `aws.backup_restore_testing`.

### 20. `legacy_break_glass` role attached to AWS-managed `AdministratorAccess`

- **File:** `infra/terraform/iam.tf`, resources
  `aws_iam_role.legacy_break_glass` and
  `aws_iam_role_policy_attachment.legacy_break_glass_admin` (at the
  end of the file). The role's `policy_arn` is
  `arn:aws:iam::aws:policy/AdministratorAccess`.
- **KSI:** KSI-IAM-JIT (Authorizing Just-In-Time). Cross-mapped to
  KSI-IAM-ELP (Ensuring Least Privilege).
- **800-53 controls:** AC-6, AC-6(2).
- **Classification:** Not implemented.
- **What's present:** The role's trust policy requires MFA; assumption
  is gated to authenticated principals in the account.
- **What's missing:** Time-bound, just-in-time elevation. The role is
  a permanent grant of full account power; once assumed, the holder
  can do anything. The `platform_admin` policy elsewhere in this file
  is custom-scoped and MFA-gated; this one bypasses both ideas.
- **Why this happens in real teams:** Stood up before the
  platform_admin / readonly_auditor split; kept around "for emergency
  operations during the migration window." The kind of role that
  outlives its rationale and shows up in 3PAO audits as the highest-
  severity finding.
- **Fix:** Delete `aws_iam_role.legacy_break_glass` and the
  AdministratorAccess attachment. Use `platform_admin` for routine
  admin work (already MFA-gated and least-privilege-scoped) and
  AWS Identity Center session policies for genuine break-glass.
- **Efterlev detector:** `aws.iam_admin_policy_usage`.

### 21. No centralized log aggregation primitives

- **File:** None. The codebase declares CloudWatch log groups for the
  app and VPC flow logs, plus a CloudTrail; it does not declare any
  aggregator (Kinesis Firehose, Security Hub, log destinations,
  subscription filters, OpenSearch, or cross-account log destinations).
- **KSI:** KSI-MLA-OSM (Operating SIEM Capability) — partial.
- **800-53 controls:** AU-2, AU-3, AU-4, SI-4(2).
- **Classification:** Not implemented.
- **What's present:** Log producers (CloudWatch log groups, the
  CloudTrail trail, the VPC flow log) all collect data.
- **What's missing:** Centralization. Logs are per-resource silos;
  nothing aggregates them to a queryable store, a SIEM, or a
  cross-account log archive. KSI-MLA-OSM expects evidence of
  centralized, tamper-resistant log handling.
- **Why this happens in real teams:** SIEM integration is downstream
  of "get logs flowing." This codebase is at "logs flowing"; the SIEM
  layer is tracked for the next phase but not yet declared.
- **Fix:** Declare an `aws_kinesis_firehose_delivery_stream` to a
  log-aggregation S3 bucket, plus subscription filters from each
  CloudWatch log group to the Firehose. Or `aws_securityhub_account` +
  finding aggregator if the team wires GuardDuty (gap #17) and
  Inspector findings into Security Hub instead.
- **Efterlev detector:** `aws.centralized_log_aggregation`.

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
| 13 | KSI-CNA-IBP | Not implemented | compute.tf | `aws_instance.bastion` (no `metadata_options`) | High |
| 14 | KSI-CNA-RNT | Not implemented | network.tf | (no `aws_network_acl` declared) | Medium |
| 15 | KSI-IAM-APM | Not implemented | iam.tf | (no federated identity provider) | High |
| 16 | KSI-SVC-RUD | Not implemented | data.tf, modules/storage | (no S3 lifecycle on any bucket) | Medium |
| 17 | KSI-MLA-OSM | Not implemented | (none) | (no `aws_guardduty_detector`) | Medium |
| 18 | KSI-MLA-EVC | Not implemented | (none) | (no `aws_config_*` recorder/channel) | Medium |
| 19 | KSI-RPL-TRC | Not implemented | backups.tf | (no `aws_backup_restore_testing_plan`) | Medium |
| 20 | KSI-IAM-JIT | Not implemented | iam.tf | `aws_iam_role.legacy_break_glass` + AdministratorAccess attachment | High |
| 21 | KSI-MLA-OSM | Not implemented | (none) | (no aggregator: Firehose / Security Hub / log destinations) | Medium |

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
