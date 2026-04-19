# Compliance status — Govnotes FedRAMP Moderate

_Internal self-assessment. Last updated 2026-03-12 by the platform team.
Not a 3PAO document. Shared with the prime contractor sponsor on request._

## Summary

Govnotes is pursuing FedRAMP Moderate authorization to support our first
federal prime contract. The FedRAMP boundary is a dedicated AWS account
that is architecturally separate from our commercial production
environment. We stood up the boundary in Q4 2025 and have spent Q1 2026
aligning the infrastructure with the Moderate baseline. Target
authorization date is Q1 2027.

We believe the boundary is in good shape. The core controls — encryption,
access control, audit logging, backup, and incident response — are
implemented. Remaining work is documentation (SSP, contingency plan,
incident response plan) and a handful of procedural controls that require
sign-off from the CISO and legal.

## Self-assessed control family status

| Family | Name | Status |
|--------|------|--------|
| AC | Access Control | Implemented |
| AU | Audit and Accountability | Implemented |
| AT | Awareness and Training | In progress |
| CM | Configuration Management | Implemented |
| CP | Contingency Planning | Implemented |
| IA | Identification and Authentication | Implemented |
| IR | Incident Response | In progress |
| MA | Maintenance | Implemented |
| MP | Media Protection | Implemented |
| PS | Personnel Security | Implemented |
| PE | Physical and Environmental Protection | Inherited (AWS) |
| PL | Planning | In progress |
| RA | Risk Assessment | Implemented |
| CA | Assessment, Authorization, and Monitoring | In progress |
| SC | System and Communications Protection | Implemented |
| SI | System and Information Integrity | Implemented |
| SR | Supply Chain Risk Management | In progress |

## Narrative on key control areas

### Encryption (SC-13, SC-28)

All data at rest in the FedRAMP boundary is encrypted with customer-managed
KMS keys. This includes the application database, the analytics database,
CloudTrail logs, backups, and all S3 buckets. All KMS keys have automatic
key rotation enabled. Transport encryption is TLS 1.2 or higher; older
TLS versions are not permitted at the edge.

### Access control and authentication (AC, IA-2)

Human access is federated through our identity provider and requires MFA
for every interactive session — console, CLI, and application. IAM
policies for human users enforce MFA via a policy condition. Service
principals use scoped roles, not shared credentials. Access reviews run
quarterly.

### Audit logging (AU-2, AU-12)

CloudTrail is enabled across the account and captures all management-plane
activity. Logs are delivered to a dedicated, encrypted, versioned S3
bucket with a restrictive bucket policy. Logs are replicated to our
central SIEM for analysis and retained for the FedRAMP-mandated duration.

### Backups and contingency (CP-9, CP-10)

RDS automated backups run daily with point-in-time recovery. S3 buckets
hosting customer data use versioning and cross-region replication for
durability. Recovery procedures are documented and tested quarterly.

### Remaining work

- Finalize the System Security Plan (SSP) using the FedRAMP Moderate
  template. Drafted; awaiting CISO review.
- Complete the Contingency Plan and run the annual tabletop exercise.
- Close out supply chain risk management (SR) procedural requirements.
- Schedule the 3PAO pre-assessment for Q3 2026.

## Notes

This document is aspirational in places. It reflects where the team
intends the boundary to be by the time we enter the 3PAO assessment. An
internal gap-analysis exercise is planned for Q2 2026; findings from
that exercise will update this document.
