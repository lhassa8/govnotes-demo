# Architecture — Govnotes FedRAMP boundary

This document describes the FedRAMP Moderate authorization boundary
only. The commercial environment has its own separate architecture doc
on the engineering wiki. Staging is documented alongside its Terraform
in `infra/environments/staging/`; staging is **not** part of the
authorization boundary.

## Boundary scope

The boundary is a dedicated AWS account (`govnotes-fedramp-prod`) in
`us-east-1`. It is isolated from the commercial account — no peering,
no cross-account roles into commercial, no shared data stores.
Customer-facing traffic from federal customers terminates here and
never leaves.

We are building evidence toward the FedRAMP 20x Key Security
Indicators. The tiers below are annotated with the KSIs each piece is
intended to satisfy.

## Trust-boundary diagram

```
                        Internet
                           │
                           │  TLS 1.2+
                           ▼
              ┌──────────────────────────┐
              │  AWS WAF v2 (managed +   │   KSI-SVC-SNT
              │   rate-limit rules)      │
              └──────────────┬───────────┘
                             │
                             ▼
              ┌──────────────────────────┐
              │  app-alb (ALB)           │   KSI-SVC-SNT
              │  :443  TLS13-1-2-2021-06 │
              │  :80   fixed-404         │
              │  :8443 legacy-api (TBD)  │
              └──────┬───────────────────┘
                     │  TLS
                     ▼
         ╔═══════════════════════════════════╗
         ║  FedRAMP boundary (us-east-1)     ║
         ║                                   ║
         ║  private-app subnets (3 AZ)       ║
         ║  ┌─────────────────────────────┐  ║
         ║  │  ECS Fargate — app service  │  ║  KSI-CNA
         ║  │  (Node/Express, pino logs)  │  ║  KSI-SVC
         ║  └────────────┬──────────┬─────┘  ║
         ║               │          │        ║
         ║               ▼          ▼        ║
         ║  private-data subnets (3 AZ)      ║
         ║  ┌──────────┐   ┌──────────────┐  ║
         ║  │ RDS PG   │   │ RDS analytics│  ║  KSI-SVC-VRI
         ║  │ primary  │   │ (secondary)  │  ║  KSI-RPL
         ║  │ KMS:app  │   │ KMS:app      │  ║
         ║  └──────────┘   └──────────────┘  ║
         ║                                   ║
         ║  S3 (via modules/storage)         ║  KSI-SVC-VRI
         ║  ┌────────┐ ┌────────┐ ┌────────┐ ║  KSI-RPL-ABO
         ║  │artifact│ │ assets │ │backups │ ║
         ║  └────────┘ └────────┘ └────────┘ ║
         ║  ┌────────┐ ┌─────────────────┐   ║
         ║  │uploads │ │ internal-reports│   ║
         ║  └────────┘ └─────────────────┘   ║
         ║                                   ║
         ║  CloudTrail → cloudtrail S3       ║  KSI-MLA
         ║  VPC flow logs → CloudWatch       ║
         ║  CMKs: app, logs, assets, reports ║  KSI-SVC-VRI
         ║                                   ║
         ║  IAM                              ║  KSI-IAM
         ║  · platform_admins (MFA required) ║  KSI-IAM-MFA
         ║  · readonly_auditors              ║
         ║  · data_ops role                  ║
         ║  · app_task role                  ║
         ║  · bastion (SSM-only)             ║
         ║                                   ║
         ╚═══════════════════════════════════╝
```

## Tiers

**Edge / load balancer tier.** A public Application Load Balancer
terminates TLS for the customer-facing domain (`app.gov.govnotes.com`).
TLS certificates are provisioned through ACM. An AWS WAF v2 web ACL is
attached to the ALB and carries the managed rule groups for the OWASP
top ten plus our own rate-limit rules. A secondary listener on port
8443 serves legacy customer integrations (tracked for deprecation).
Relevant KSIs: KSI-SVC, KSI-SVC-SNT.

**Application tier.** The Express/Node application runs as a service on
ECS Fargate. Tasks pull images from a private ECR repository. Tasks run
in private subnets with no direct inbound internet reachability;
outbound internet goes through NAT gateways for package and telemetry
traffic. Relevant KSIs: KSI-CNA, KSI-SVC.

**Data tier.** PostgreSQL runs on RDS with Multi-AZ. A secondary
analytics database is maintained on a smaller RDS instance for internal
reporting. S3 buckets hold application artifacts, static assets,
CloudTrail logs, backups, customer attachments, and the internal
reports export. All production-boundary S3 buckets are created through
the `storage` module. Relevant KSIs: KSI-SVC-VRI, KSI-RPL.

**Observability tier.** CloudWatch for metrics and logs. CloudTrail for
management-plane audit. VPC flow logs into CloudWatch. Logs are
streamed to our central SIEM via EventBridge. Relevant KSIs: KSI-MLA.

## Identity and access

Human access to the FedRAMP account is federated through our identity
provider. All interactive console and CLI access requires MFA.

- `platform_admins` — operator group, policy carries
  `aws:MultiFactorAuthPresent` on every action.
- `readonly_auditors` — auditor group with read-only permissions;
  policy predates the MFA rollout.
- `data_ops` — role assumed by the data team's workstations for ETL
  and backfills; MFA is required for destructive actions but not for
  reads and writes.
- `app_task` — ECS task role, narrow S3/CloudWatch permissions.
- `bastion` — EC2 instance-profile, SSM-managed only.
- `ci-deploy` — legacy IAM user with programmatic access keys, used by
  the Jenkins pipeline until the GitHub Actions OIDC migration lands.

Relevant KSIs: KSI-IAM, KSI-IAM-MFA.

## Encryption

Data at rest in RDS and the majority of S3 buckets is encrypted with
customer-managed KMS keys. TLS 1.2+ terminates at the ALB. Internal
traffic between ECS tasks and RDS is TLS. The `app` and `logs` CMKs
have automatic key rotation enabled. The `assets` CMK is on a manual
rotation schedule. The `reports` CMK is attached to the internal
reports bucket. Relevant KSIs: KSI-SVC-VRI.

## Out of scope for this repo

- The commercial production environment.
- Corporate IT systems (Okta, Google Workspace, etc.).
- Customer-managed devices.
- Third-party SaaS vendors outside the authorization boundary.
- The staging environment in `infra/environments/staging/`.
