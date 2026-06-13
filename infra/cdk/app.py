#!/usr/bin/env python3
"""CDK app entry point for the GovNotes async-ingest pipeline."""
import aws_cdk as cdk

from stacks.ingest_stack import IngestStack

app = cdk.App()
IngestStack(app, "govnotes-ingest")
app.synth()
