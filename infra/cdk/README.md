# GovNotes async-ingest pipeline (AWS CDK, Python)

The third IaC surface in this demo, alongside `infra/terraform/` and
`infra/cloudformation/`. Efterlev's CDK **source-mode** reads these `.py`
files directly (no `cdk synth` needed) and emits construct-presence
evidence with `.py` file:line citations — the inventory layer.

Source-mode is intentionally narrow: it proves WHICH constructs exist and
WHERE, not how they are configured. Property-level posture (encryption
settings, public-access flags, retention) comes from synth-mode: run
`cdk synth` and let Efterlev scan the emitted CloudFormation. The two
compose; see Efterlev's LIMITATIONS.md "CDK source-mode" section.

This stack is deliberately small: an async ingest pipeline (queue →
function → table, with a dead-letter topic and an explicit log group)
that the GovNotes app would use for attachment processing.
