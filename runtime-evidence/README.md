# Runtime evidence (synthetic)

Pre-existing runtime-tool output that Efterlev ingests alongside the IaC
scan (`efterlev import-security-hub` / `import-config`; default-on since
v0.1.124). Both files are **synthetic** — hand-crafted from the AWS ASFF /
Config API specs against this demo's resource names. No AWS account
produced them; zero AWS spend.

Why this matters for 20x: static config-as-evidence shows *intent*;
runtime findings show *reality*. The interesting case is when they
disagree — see deliberate gap #28 (the `app_uploads` bucket: Terraform
declares a public-access block, the Security Hub finding says the live
bucket is publicly readable). A reviewer should see BOTH evidence records
on the same KSI and treat the drift itself as the finding.

Import them after `efterlev init` (the scan workflow does this):

    efterlev import-security-hub runtime-evidence/security-hub-findings.json
    efterlev import-config runtime-evidence/config-evaluations.json
