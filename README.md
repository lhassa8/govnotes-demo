# Govnotes

Govnotes is a secure note-taking and knowledge-management product for
government agencies and federal contractors. This repository contains the
infrastructure-as-code and application source for the **FedRAMP boundary**
of the Govnotes platform.

This boundary runs in a dedicated AWS account, separate from the commercial
production environment that serves our SaaS customers today. The code here
is in active development as part of our FedRAMP Moderate authorization
effort, which we are pursuing via the **FedRAMP 20x** pathway. We are
building evidence toward the 20x Key Security Indicators (KSIs) and
expect to enter 3PAO assessment in Q1 2027.

## Repository layout

```
govnotes/
├── app/                       Node.js / Express application source
├── infra/terraform/           Terraform for the FedRAMP prod boundary
├── infra/terraform/modules/   Shared modules (storage)
├── infra/environments/staging Staging — NOT in the FedRAMP boundary
├── docs/                      Architecture and compliance docs
├── CHANGELOG.md               Running changelog for the boundary
├── DELIBERATE_GAPS.md         Ground-truth list of known gaps
└── .github/workflows/         CI: lint, test, terraform fmt + validate
```

## What Govnotes the product does

Govnotes gives mission teams a shared, searchable, audit-logged workspace
for notes, meeting summaries, and institutional knowledge. Content stays
within customer-controlled boundaries. Every read and every write is
logged. Admins control access by role, project, and classification tag.

The commercial edition has been generally available since 2022 and is
SOC 2 Type II audited. The FedRAMP edition (this codebase) is a ground-up
rebuild of the same product on a hardened boundary.

## Running the application locally

The app is the easier half of the repo to run locally. You need Node
20.x and a running Postgres 15 instance. From the `app/` directory:

```
cp .env.example .env            # then fill in the blanks
npm install
npm run db:migrate
npm run dev
```

The server listens on port 3000 by default. `GET /health` should return
`{"status":"ok"}`.

A caveat: this is an infrastructure-first repo, and the application is
intentionally minimal. Most of the platform's real behavior lives in the
commercial codebase; this codebase is focused on getting the FedRAMP
boundary right. Expect thin routes and thin tests.

## Deploying via Terraform

```
cd infra/terraform
terraform init
terraform plan -var-file=prod.tfvars
terraform apply -var-file=prod.tfvars
```

A caveat: a real deploy requires an S3 remote state bucket, a DynamoDB
lock table, and an assumed role with the right permissions in the
FedRAMP AWS account. See `infra/terraform/README.md` for details.

Do not run `terraform apply` against the FedRAMP account without going
through the change-management process documented on the engineering wiki.

## Documentation

- [`docs/architecture.md`](docs/architecture.md) — high-level architecture
  of the FedRAMP boundary.
- [`docs/compliance-status.md`](docs/compliance-status.md) — our internal
  self-assessment, structured around the FedRAMP 20x KSIs.
- [`CHANGELOG.md`](CHANGELOG.md) — running log of changes to the
  boundary, including known follow-ups.

## License

Apache License 2.0. See [`LICENSE`](LICENSE).
