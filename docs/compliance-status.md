# Compliance status — Govnotes FedRAMP 20x

_Internal self-assessment. Last updated 2026-04-10 by the platform team.
Not a 3PAO document. Shared with the prime contractor sponsor on request._

## Summary

Govnotes is pursuing FedRAMP Moderate authorization via the **FedRAMP
20x** pathway and has been reviewing the Key Security Indicators (KSIs)
guidance against our FedRAMP boundary. The boundary is a dedicated AWS
account architecturally separated from our commercial production
environment.

We believe the boundary is in good shape. The core KSIs — cloud-native
architecture, service configuration, identity and access, logging and
audit, and recovery planning — are implemented to the 20x expectations.
Remaining work is mostly documentation (SSP, contingency plan,
incident response plan) and a handful of procedural KSIs that need
CISO and legal sign-off.

## KSI-level self-assessment

| KSI | Name | Status |
|-----|------|--------|
| KSI-CNA | Cloud Native Architecture | Implemented |
| KSI-SVC | Service Configuration | Implemented |
| KSI-SVC-SNT | Securing Network Traffic | Implemented |
| KSI-SVC-VRI | Validating Resource Integrity | Implemented |
| KSI-IAM | Identity and Access Management | Implemented |
| KSI-IAM-MFA | Phishing-Resistant MFA | Implemented |
| KSI-MLA | Monitoring, Logging, Auditing | Implemented |
| KSI-CMT | Change Management | Implemented |
| KSI-PIY | Policy and Inventory | In progress |
| KSI-RPL | Recovery Planning | Implemented |
| KSI-RPL-ABO | Recovery — Backups | Implemented |
| KSI-TPR | Third-Party Resources | In progress |
| KSI-CED | Cybersecurity Education | In progress |
| KSI-IRP | Incident Response | In progress |

## Narrative on key KSI areas

### KSI-SVC-VRI — Resource integrity and encryption

All data at rest in the FedRAMP boundary is encrypted with
customer-managed KMS keys. This includes the application database, the
analytics database, CloudTrail logs, backups, and all S3 buckets. All
production KMS keys have automatic key rotation enabled. Transport
encryption is TLS 1.2 or higher at the customer edge; older TLS
versions are not permitted.

### KSI-SVC-SNT — Network traffic protection

Customer traffic terminates at the ALB with a modern TLS policy. The
ALB is fronted by AWS WAF. The application tier runs in private
subnets with no direct inbound reachability from the internet.
Internal traffic between the app tier and the data tier is protected
by security groups scoped to the app service role.

### KSI-IAM — Identity and access

Human access is federated through our identity provider. Service
principals use scoped IAM roles rather than shared credentials.
Privileged actions run through MFA-protected roles. Access reviews
run quarterly.

### KSI-IAM-MFA — Phishing-resistant MFA

Multi-factor authentication is enforced for all administrative access
to the FedRAMP boundary. IAM policies for human users include the
`aws:MultiFactorAuthPresent` condition, and the federation provider
requires hardware-backed factors.

### KSI-MLA — Monitoring, logging, auditing

Comprehensive audit logging is in place across all regions. CloudTrail
captures management-plane activity and delivers to a dedicated,
encrypted, versioned S3 bucket. VPC flow logs are captured into
CloudWatch. Logs are replicated to our central SIEM for correlation
and retained for the FedRAMP-mandated duration.

### KSI-RPL — Recovery planning and backups

RDS automated backups run daily with multi-day retention and
point-in-time recovery. The AWS Backup plan provides a 35-day daily
and 90-day weekly schedule across critical resources. S3 buckets
holding customer data use versioning, and backup objects are protected
by KMS. Recovery procedures are documented and tested quarterly.

### Remaining work

- Finalize the SSP using the FedRAMP 20x machine-readable evidence
  package. Drafted; awaiting CISO review.
- Close out the Contingency Plan and run the annual tabletop exercise.
- Complete third-party vendor review (KSI-TPR) for the two remaining
  SaaS integrations.
- Schedule the 3PAO pre-assessment for Q3 2026.

## Notes

This document is aspirational in places. It reflects where the team
intends the boundary to be by the time we enter 3PAO assessment. An
internal gap analysis is planned for Q2 2026; findings from that
exercise will update this document.
