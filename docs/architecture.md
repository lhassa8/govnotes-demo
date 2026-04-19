# Architecture — Govnotes FedRAMP boundary

This document describes the FedRAMP Moderate boundary only. The commercial
environment has its own separate architecture document on the engineering
wiki.

## Boundary scope

The FedRAMP boundary is a dedicated AWS account (`govnotes-fedramp-prod`)
in the `us-east-1` region. It is completely separate from the commercial
account. No peering, no cross-account roles into commercial, no shared
data stores. Customer-facing traffic from federal customers terminates
here and never leaves.

## Tiers

**Edge / load balancer tier.** A public Application Load Balancer
terminates TLS for the customer-facing domain (`app.gov.govnotes.com`).
TLS certificates are provisioned through ACM. An AWS WAF v2 web ACL is
attached to the ALB and carries the managed rule groups for the OWASP
top ten plus our own rate-limit rules.

**Application tier.** The Express/Node application runs as a service on
ECS Fargate. Tasks pull images from a private ECR repository. Tasks run
in private subnets with no direct inbound internet reachability; outbound
internet goes through NAT gateways for package and telemetry traffic.

**Data tier.** PostgreSQL runs on RDS with Multi-AZ. A secondary
analytics database is maintained on a smaller RDS instance for internal
reporting. S3 buckets hold application artifacts (build outputs, static
assets), CloudTrail logs, backups, and user-uploaded file attachments.

**Observability tier.** CloudWatch for metrics and logs. CloudTrail for
management-plane audit. Logs are streamed out of the account to our
central SIEM via an EventBridge rule and a cross-account delivery role.

## Identity and access

Human access to the FedRAMP account is federated through our identity
provider. All interactive console and CLI access requires MFA. Service
roles are scoped per workload. A small number of long-lived IAM
credentials exist for legacy CI jobs that we have not yet migrated to
OIDC; those are tracked as technical debt.

## Encryption

Data at rest in RDS and the majority of S3 buckets is encrypted with
customer-managed KMS keys. TLS 1.2+ terminates at the ALB. Internal
traffic between ECS tasks and RDS is also TLS. KMS keys used for
sensitive data have automatic key rotation enabled.

## Boundary diagram

A one-page PDF of the boundary diagram lives on the engineering wiki at
`wiki/fedramp/boundary-diagram.pdf` and is updated by the platform team
each sprint.

## Out of scope for this repo

- The commercial production environment.
- Our shared corporate IT systems (Okta, Google Workspace, etc.).
- Customer-managed devices.
- Third-party SaaS vendors outside the authorization boundary.
