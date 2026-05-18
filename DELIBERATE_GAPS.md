# Deliberate gaps in govnotes

This document is the ground-truth catalog of the compliance gaps that
exist in this repository on purpose. Govnotes is a synthetic FedRAMP
20x boundary codebase used as a scanning target — the gaps are placed
here so automated compliance tooling has known findings to match
against.

Every gap below is:

- **Realistic.** It mirrors a mistake a distracted engineering team
  would plausibly make during a real FedRAMP 20x build-out.
- **Scoped.** The production boundary is ground-truthed across BOTH
  IaC representations: `infra/terraform/` (the authoritative source)
  and `infra/cloudformation/` (the mirror added to prove Efterlev's
  IaC-agnostic scanning). Each gap below appears in BOTH; the
  CloudFormation cross-reference table below maps each TF location to
  its CFN counterpart. The `infra/environments/staging/` environment
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

## CloudFormation cross-reference

Each gap below has a paired entry in `infra/cloudformation/`. The
CFN representation uses CamelCase resource names; the gap shape (no
encryption block, no rotation rule, missing public-access-block
fields, etc.) is preserved exactly so Efterlev classifications stay
consistent across the two IaC paths.

| TF resource                                                    | CFN equivalent                                                    |
| -------------------------------------------------------------- | ----------------------------------------------------------------- |
| `aws_s3_bucket "user_uploads"` (storage module)                | `03-storage.yaml` UserUploadsBucket (no `BucketEncryption`)       |
| `aws_kms_key "assets"` (rotation disabled)                     | `02-kms.yaml` AssetsCmk (`EnableKeyRotation: false`)              |
| `aws_kms_key "reports"` (broad account-wide policy)            | `02-kms.yaml` ReportsCmk (`Principal: AWS: "*"`)                  |
| `aws_secretsmanager_secret "db_url"` (no rotation)             | `04-data.yaml` DbUrlSecret (no `RotationRules`)                   |
| `aws_secretsmanager_secret "jwt_signing_key"` (no rotation)    | `04-data.yaml` JwtSigningKeySecret (no `RotationRules`)           |
| `aws_lb_listener "http"` (port 80, fixed-404, no redirect)     | `06-loadbalancer.yaml` HttpListener (`fixed-response 404`)        |
| `aws_lb_listener "legacy_api"` (TLS-2016-08 policy)            | `06-loadbalancer.yaml` LegacyApiListener (`ELBSecurityPolicy-2016-08`) |
| `aws_iam_user "ci_deploy"` + `aws_iam_access_key`              | `07-iam.yaml` CiDeployUser + CiDeployAccessKey                    |
| `aws_iam_role_policy_attachment "legacy_break_glass_admin"`    | `07-iam.yaml` LegacyBreakGlassRole (AdministratorAccess)          |
| `aws_iam_policy "readonly_auditor"` (no MFA condition)         | `07-iam.yaml` ReadonlyAuditorPolicy (no MFA condition)            |
| `aws_iam_policy "data_ops"` (R/W without MFA)                  | `07-iam.yaml` DataOpsRole (R/W without MFA condition)             |
| `aws_ebs_volume "bastion_scratch"` (unencrypted)               | `05-compute.yaml` BastionScratchVolume (`Encrypted: false`)       |
| `aws_cloudtrail "main"` (log-file validation disabled)         | `08-logging.yaml` MainTrail (`EnableLogFileValidation: false`)    |
| `aws_cloudwatch_log_group "experiments"` (no retention)        | `08-logging.yaml` ExperimentsLogGroup (no `RetentionInDays`)      |
| `aws_cloudwatch_log_group "integrations"` (no CMK)             | `08-logging.yaml` IntegrationsLogGroup (no `KmsKeyId`)            |
| `aws_s3_bucket "legacy_export"` (no encryption block)          | `03-storage.yaml` LegacyExportBucket (no `BucketEncryption`)      |
| `aws_s3_bucket "temp_data_pipeline"` (no encryption, no PAB)   | `03-storage.yaml` TempDataPipelineBucket (no encryption, no PAB)  |
| `aws_s3_bucket_public_access_block "ml_training_data"` (partial) | `03-storage.yaml` MlTrainingDataBucket (only 2 of 4 fields)     |
| `aws_s3_bucket "internal_reports"` (no versioning)             | `03-storage.yaml` InternalReportsBucket (no `VersioningConfiguration`) |

When you add/remove/edit a gap, update BOTH IaC representations AND the
per-gap entry below in the same commit so the ground truth stays
consistent across the two paths.

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

## CI / supply-chain gaps — `.github/workflows/*.yml`

Efterlev's GitHub-workflow detectors read the same way Terraform-source
detectors do — each `.github/workflows/*.yml` file is a "resource" and
each `uses:` step is inspected for security-relevant signals. The gaps
below are observable from `.github/workflows/{ci,terraform-check,
efterlev-scan}.yml` as they currently sit in this repo.

### 22. GitHub Actions pin posture is mixed (some SHA-pinned, most by tag)

- **File:** `.github/workflows/ci.yml`,
  `.github/workflows/terraform-check.yml`,
  `.github/workflows/efterlev-scan.yml` — all use major-version tags
  (`@v3`, `@v4`, `@v5`). `.github/workflows/security-scan.yml` and
  `.github/workflows/release-deploy.yml` mix posture: official
  `actions/*` steps pinned by tag, third-party `anchore/sbom-action`
  and `slackapi/slack-github-action` pinned by 40-hex SHA.
- **KSI:** KSI-SCR-MIT (Mitigating Supply Chain Risk).
- **800-53 controls:** SR-5, SI-7(1).
- **Classification:** Partial. Two of five workflows are partial-
  posture (some SHA-pinned, some tag-pinned); the other three are
  fully tag-pinned. The Gap Agent should distinguish these.
- **What's present:** Workflows use named, well-known third-party
  actions (`actions/checkout`, `actions/setup-python`,
  `hashicorp/setup-terraform`).
- **What's missing:** Immutability. A compromised tag (the
  attack pattern that landed `tj-actions/changed-files@v44` malware
  in early 2025) re-points the action to attacker-controlled code on
  the next workflow run; SHA-pinning prevents that by tying the
  reference to a specific commit's content hash.
- **Why this happens in real teams:** Floating-tag is the default in
  every action's README. SHA pinning requires a tooling layer
  (Dependabot's github-actions ecosystem opens PRs for SHA bumps;
  without it, the team has to maintain SHAs by hand).
- **Fix:** Replace each `@vN` with `@<full-40-hex-sha>` and a trailing
  `# vN` comment for human readability. Enable the `github-actions`
  Dependabot ecosystem in a `.github/dependabot.yml` so updates land
  as reviewable PRs.
- **Efterlev detector:** `github.action_pinning`.

### 23. SBOM generation is in place but no CVE scan is wired up

- **File:** `.github/workflows/security-scan.yml` runs
  `anchore/sbom-action` on every push to main and on a weekly
  schedule, generating a CycloneDX SBOM. None of the workflows
  invoke `grype`, `trivy`, `snyk test`, `osv-scanner`, `pip-audit`,
  or any equivalent CVE scanner.
- **KSI:** KSI-SCR-MON (Monitoring Supply Chain Risk).
- **800-53 controls:** RA-5, SR-3.
- **Classification:** Partial. SBOM tooling counts as evidence
  toward KSI-SCR-MON (it's the canonical "what's in our deps?"
  artifact), but without a CVE scanner the SBOM is descriptive,
  not actionable. The supply-chain monitoring detector should
  surface `sbom_present=true, cve_scan_present=false`.
- **What's present:** Per-language test runners (`npm test` for the
  app, `terraform validate` for the infra). Lint passes in CI.
- **What's missing:** Automated supply-chain monitoring. CVEs in
  upstream dependencies (Node packages, Terraform providers, base
  images) reach `main` undetected. KSI-SCR-MON specifically asks for
  *automated monitoring of third-party software for upstream
  vulnerabilities*; manual review at upgrade time doesn't qualify.
- **Why this happens in real teams:** SCA tooling has fragmented in
  the last two years (`trivy`, `grype`, `osv-scanner`, `dependency-
  track` all overlap differently); teams defer the choice and ship
  without one.
- **Fix:** Add a `scan` job to `.github/workflows/ci.yml` that runs
  `trivy fs --scanners vuln,license,secret,config .` (one tool, broad
  coverage) and uploads SARIF findings to GitHub's Code-Scanning tab.
  Equivalently, run `syft . -o cyclonedx-json | grype` for an
  SBOM-then-scan flow.
- **Efterlev detector:** `github.supply_chain_monitoring`.

### 24. Declarative-deploy workflow exists but is mostly-not-fully immutable

- **File:** `.github/workflows/release-deploy.yml` runs `terraform
  apply` against `infra/terraform/` on `v*.*.*` tag pushes. The
  declarative-deploy posture is correct, BUT a follow-up step does
  `aws s3 sync ./app/static-assets/ s3://...` — an imperative
  mutation outside Terraform's surface. The static-asset bundling
  isn't yet wrapped into Terraform.
- **KSI:** KSI-CMT-RMV (Redeploying vs Modifying via immutable
  pipelines).
- **800-53 controls:** CM-2, CM-7.
- **Classification:** Partial. The infra-layer deploy is fully
  declarative; the asset-layer deploy is imperative. Real-world
  mid-journey state — most teams ship the IaC-managed pieces
  before fully Terraform-izing build artifacts and content.
- **What's present:** Workflow-driven validation (`terraform fmt`,
  `terraform validate`).
- **What's missing:** Workflow-driven deployment. `terraform apply`
  runs from operator laptops with the long-lived `ci_deploy` access
  key, not from a CI workflow that re-applies the version-controlled
  baseline. KSI-CMT-RMV asks customers to *execute changes through
  redeployment of version-controlled immutable resources rather than
  direct modification*; this codebase ships the version-controlled
  resources but the modification path remains direct.
- **Why this happens in real teams:** The `ci_deploy → OIDC migration`
  in PLAT-1184 (referenced in gap #8) is the prerequisite — once
  that lands, an `apply.yml` workflow assuming a federated role
  becomes plausible. Until then, the workstation-apply pattern
  persists.
- **Fix:** After PLAT-1184 ships (federation + deploy role),
  add `.github/workflows/apply.yml` that runs on `workflow_dispatch`
  + tag pushes, assumes the deploy role via OIDC, and runs
  `terraform plan` then `terraform apply` against the boundary.
  Gate behind a `production` environment with required reviewers.
- **Efterlev detector:** `github.immutable_deploy_patterns`.

---

## Partial-state surfaces — `s3.tf`, `logging.tf`

Tier 1 coverage expansion adds bucket-by-bucket and log-group-by-log-
group variance — exactly the texture a 3PAO surfaces in scoping. The
Gap Agent must distinguish `partial` from `not_implemented` when a
workspace has *some* compliant resources alongside *some* gaps;
without varied posture in the dogfood fixture, partial classifications
were under-exercised.

### 25. S3 buckets have mixed encryption / public-block / versioning posture

- **File:** `infra/terraform/s3.tf`. Six buckets, posture matrix:

  | bucket             | enc       | kms          | public_block | versioning |
  |--------------------|-----------|--------------|--------------|------------|
  | app_uploads        | aws:kms   | CMK (app)    | all 4 = true | enabled    |
  | static_assets      | AES256    | aws-managed  | all 4 = true | enabled    |
  | internal_reports   | aws:kms   | CMK (reports)| all 4 = true | absent     |
  | ml_training_data   | AES256    | aws-managed  | partial (2/4)| absent     |
  | legacy_export      | absent    | —            | all 4 = true | absent     |
  | temp_data_pipeline | absent    | —            | absent       | absent     |

- **KSIs:** KSI-SVC-VRI (Validating Resource Integrity — encryption-at-
  rest posture), KSI-SVC-PRR (Preventing Residual Risk — CMK control
  over data assets), KSI-CNA-MAT (Minimizing Attack Surface —
  public-access block).
- **800-53 controls:** SC-28, SC-28(1), AC-3.
- **Classification:** Partial across all three KSIs. Some buckets
  meet the standard, some don't, some partially do (ml_training_data
  has 2 of 4 public-block flags set).
- **What's present:** 4 of 6 buckets have encryption configured;
  5 of 6 have a public-access block (3 of those fully-restrictive,
  1 partial); 2 of 6 have versioning.
- **What's missing:** Uniform posture. `legacy_export` and
  `temp_data_pipeline` need encryption blocks; `internal_reports`
  needs versioning; `ml_training_data` needs the remaining two
  public-block flags.
- **Why this happens in real teams:** Buckets accrete over time
  with different owners. The fully-compliant `app_uploads` was
  created last quarter when the security policy tightened;
  `legacy_export` predates the policy and the consumer (a partner)
  expects unencrypted CSVs.
- **Fix:** Add `aws_s3_bucket_server_side_encryption_configuration`
  for `legacy_export` and `temp_data_pipeline`; add
  `aws_s3_bucket_public_access_block` (all 4 = true) for
  `temp_data_pipeline`; flip `ml_training_data`'s
  `block_public_policy` and `restrict_public_buckets` to true once
  the partner integration moves to a federated role; add
  `aws_s3_bucket_versioning` to `internal_reports`.
- **Efterlev detectors:** `aws.encryption_s3_at_rest`,
  `aws.s3_public_access_block`, `aws.s3_versioning`,
  `aws.kms_key_rotation`.

### 26. CloudWatch log groups have mixed retention + KMS encryption

- **File:** `infra/terraform/logging.tf`. Four log groups:

  | log group         | retention_in_days | kms_key_id   |
  |-------------------|-------------------|--------------|
  | vpc_flow_logs     | 365               | logs CMK     |
  | app_runtime       | 365               | logs CMK     |
  | experiments       | unset (never)     | logs CMK     |
  | integrations      | 30                | unset        |

- **KSIs:** KSI-MLA-LET (Logging Event Types — covers retention as
  part of "logging the right events long enough to investigate").
- **800-53 controls:** AU-11, AU-9.
- **Classification:** Partial. Two log groups meet the standard
  (vpc_flow_logs, app_runtime); two don't (experiments has no
  retention; integrations has no KMS encryption).
- **What's present:** 3 of 4 log groups have retention; 3 of 4
  have CMK encryption.
- **What's missing:** Uniformity. `experiments` defaults to
  never-expire (storage cost grows unbounded; AU-11 wants a
  defined retention period). `integrations` has retention but
  the partner-integration debug data isn't KMS-encrypted at rest.
- **Why this happens in real teams:** Log groups proliferate
  faster than the retention policy gets re-applied. The
  Terragrunt-aspect rollout is in progress.
- **Fix:** Add `retention_in_days = 30` to `experiments`; add
  `kms_key_id = aws_kms_key.logs.arn` to `integrations`.
- **Efterlev detectors:** `aws.cloudwatch_log_retention`,
  `aws.cloudwatch_log_encryption`.

### 27. Dev sandbox subtree is OUT OF FedRAMP boundary

- **File:** `infra/terraform/dev_sandbox/main.tf`. A dev RDS
  instance and S3 bucket with deliberately mis-configured posture
  (no encryption, hardcoded password, no backups). The boundary
  is declared in the workspace's `.efterlev/config.toml` (applied
  by the `efterlev-scan` workflow) as:

      [boundary]
      include = ["infra/terraform/**"]
      exclude = ["infra/terraform/dev_sandbox/**"]

- **KSI:** N/A — boundary scoping is a 3PAO concern, not a KSI.
- **Classification:** Out of boundary. Detectors should still emit
  Evidence for these resources (so you can SEE them with
  `efterlev provenance show`), but the boundary filter must drop
  them from the POA&M.
- **What's present:** Resources exist, are scanned, are surfaced
  with `boundary_state = "out_of_boundary"`.
- **What's missing:** Nothing — this is a positive test case for
  the boundary mechanism. If POA&M items appear for `dev_scratch`
  resources, the boundary filter has regressed.
- **Why this happens in real teams:** Dev workloads live in a
  separate AWS account in production setups. Keeping it in-repo
  here is a deliberate fixture — same repo, same scan, but
  out-of-scope for the FedRAMP package.
- **Efterlev mechanism:** `[boundary]` section of
  `.efterlev/config.toml` + `BoundaryConfig.classify_path()` at
  Evidence-emission time.

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
| 22 | KSI-SCR-MIT | Partially implemented | .github/workflows/* | Mixed pin posture across 5 workflows (3 tag-pinned, 2 mixed) | Medium |
| 23 | KSI-SCR-MON | Partially implemented | .github/workflows/security-scan.yml | SBOM via syft, no CVE scan | Medium |
| 24 | KSI-CMT-RMV | Partially implemented | .github/workflows/release-deploy.yml | `terraform apply` + imperative `aws s3 sync` | Medium |
| 25 | KSI-SVC-VRI, KSI-SVC-PRR, KSI-CNA-MAT | Partially implemented | s3.tf | 6 buckets, mixed encryption / public-block / versioning posture | Medium |
| 26 | KSI-MLA-LET | Partially implemented | logging.tf | 4 log groups, mixed retention + KMS posture | Medium |
| 27 | (out of boundary) | — | dev_sandbox/main.tf | `dev_scratch` RDS + S3 — boundary excludes the subtree | N/A |

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
