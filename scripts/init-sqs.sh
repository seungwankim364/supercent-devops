#!/bin/sh
# Initialize SQS in LocalStack: a main queue + a Dead Letter Queue (DLQ)
# wired together with a native redrive policy.
#
# Behavior: when the worker fails to process a message, it does NOT delete it,
# so the message becomes visible again after the visibility timeout. After
# maxReceiveCount (5) failed receives, SQS automatically moves the message to
# the DLQ. This mirrors the AWS setup in terraform/log_storage.tf.

set -e

ENDPOINT="http://localstack:4566"
MAIN_QUEUE="supercent-queue"
DLQ_QUEUE="supercent-queue-dlq"
MAX_RECEIVE_COUNT=5

echo "[init-sqs] Creating DLQ: ${DLQ_QUEUE}"
DLQ_URL=$(aws --endpoint-url="${ENDPOINT}" sqs create-queue \
  --queue-name "${DLQ_QUEUE}" \
  --query 'QueueUrl' --output text)

DLQ_ARN=$(aws --endpoint-url="${ENDPOINT}" sqs get-queue-attributes \
  --queue-url "${DLQ_URL}" \
  --attribute-names QueueArn \
  --query 'Attributes.QueueArn' --output text)

echo "[init-sqs] DLQ ARN: ${DLQ_ARN}"

echo "[init-sqs] Creating main queue: ${MAIN_QUEUE}"
MAIN_URL=$(aws --endpoint-url="${ENDPOINT}" sqs create-queue \
  --queue-name "${MAIN_QUEUE}" \
  --query 'QueueUrl' --output text)

echo "[init-sqs] Attaching redrive policy (maxReceiveCount=${MAX_RECEIVE_COUNT})"
# RedrivePolicy's value is itself a JSON string, so pass --attributes as a
# JSON file (file://) to avoid the CLI shorthand parser choking on the commas.
printf '{"RedrivePolicy":"{\\"deadLetterTargetArn\\":\\"%s\\",\\"maxReceiveCount\\":\\"%s\\"}"}' \
  "${DLQ_ARN}" "${MAX_RECEIVE_COUNT}" > /tmp/redrive.json

aws --endpoint-url="${ENDPOINT}" sqs set-queue-attributes \
  --queue-url "${MAIN_URL}" \
  --attributes file:///tmp/redrive.json

echo "[init-sqs] Done. main=${MAIN_QUEUE} dlq=${DLQ_QUEUE}"
