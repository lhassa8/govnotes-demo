"""Async attachment-ingest pipeline for GovNotes.

Demonstrates both CDK import styles Efterlev's source-mode parses:
module-alias (`from aws_cdk import aws_sqs as sqs`) and direct
(`from aws_cdk.aws_dynamodb import Table`).
"""

from aws_cdk import Duration, Stack
from aws_cdk import aws_lambda as lambda_
from aws_cdk import aws_logs as logs
from aws_cdk import aws_sns as sns
from aws_cdk import aws_sqs as sqs
from aws_cdk.aws_dynamodb import Attribute, AttributeType, Table
from constructs import Construct


class IngestStack(Stack):
    """Queue -> processor -> table, with a DLQ alert topic."""

    def __init__(self, scope: Construct, construct_id: str, **kwargs: object) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Attachment-processing queue. Encryption is SQS-managed by CDK
        # default; the posture detail is only visible in synth-mode.
        ingest_queue = sqs.Queue(
            self,
            "AttachmentIngestQueue",
            visibility_timeout=Duration.seconds(300),
        )

        # Dead-letter alert fan-out for the on-call channel.
        dlq_alerts = sns.Topic(self, "IngestDlqAlerts")

        # Explicit log group so retention is declared, not implicit.
        processor_logs = logs.LogGroup(self, "IngestProcessorLogs")

        # The processor itself.
        processor = lambda_.Function(
            self,
            "AttachmentProcessor",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="processor.handler",
            code=lambda_.Code.from_asset("lambda/processor"),
            timeout=Duration.seconds(120),
        )

        # Processed-attachment metadata.
        attachments_table = Table(
            self,
            "AttachmentMetadata",
            partition_key=Attribute(name="note_id", type=AttributeType.STRING),
            sort_key=Attribute(name="attachment_id", type=AttributeType.STRING),
        )

        # Wire-up is app-level concern; kept minimal for the demo.
        _ = (ingest_queue, dlq_alerts, processor_logs, processor, attachments_table)
