# Evidence Manifests

This directory holds **customer-authored, human-signed procedural attestations**
for FedRAMP 20x KSIs whose evidence is not observable from the Terraform
scanner alone. Each `*.yml` file binds to exactly one KSI and contains one
or more attestation entries.

The manifest loader (Efterlev's `load_evidence_manifests` primitive) reads
every `.yml` file under this directory at scan time, validates each against
the manifest schema, and emits one `Evidence` record per attestation with
`detector_id="manifest"`. These Evidence records flow into the Gap Agent
alongside detector-emitted Evidence.

## Why these are committed to source control

Evidence Manifests are **part of your compliance posture**. They go through
code review like any other change to the repo. The attestor is a real
person with a name and an email; the date the attestation was signed is
recorded; the next-review date is set so the manifest can't go stale
silently.

3PAOs reading this directory can see exactly which assertions Efterlev's
output is grounded in.

## Coverage

This directory currently attests three procedural-only KSIs the IaC
scanner cannot evidence:

| File | KSI | Theme |
|---|---|---|
| `afr-fsi-security-inbox.yml` | KSI-AFR-FSI | Authorization Framework Reciprocity |
| `ced-rgt-security-training.yml` | KSI-CED-RGT | Cybersecurity Education |
| `inr-rir-incident-response.yml` | KSI-INR-RIR | Incident Response |

These three sit in themes (AFR, CED, INR) where the entire KSI bar is
procedural — there's no Terraform pattern that proves "we have a
security inbox" or "we run security awareness training." Manifests are
the only mechanism that lets these KSIs be classified as anything other
than `evidence_layer_inapplicable`.
