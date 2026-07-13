set -e

ENDPOINT="http://localstack:4566"
MAIN_QUEUE="supercent-queue"
DLQ_QUEUE="supercent-queue-dlq"
MAX_RECEIVE_COUNT=5

# 1) 먼저 DLQ를 생성한다. (메인 큐의 redrive 정책이 DLQ의 ARN을 참조하므로 DLQ가 먼저 있어야 함)
echo "[init-sqs] Creating DLQ: ${DLQ_QUEUE}"
DLQ_URL=$(aws --endpoint-url="${ENDPOINT}" sqs create-queue \
  --queue-name "${DLQ_QUEUE}" \
  --query 'QueueUrl' --output text)

# redrive 정책에 넣을 DLQ의 ARN을 조회한다.
DLQ_ARN=$(aws --endpoint-url="${ENDPOINT}" sqs get-queue-attributes \
  --queue-url "${DLQ_URL}" \
  --attribute-names QueueArn \
  --query 'Attributes.QueueArn' --output text)

echo "[init-sqs] DLQ ARN: ${DLQ_ARN}"

# 2) 메인 큐를 생성한다.
echo "[init-sqs] Creating main queue: ${MAIN_QUEUE}"
MAIN_URL=$(aws --endpoint-url="${ENDPOINT}" sqs create-queue \
  --queue-name "${MAIN_QUEUE}" \
  --query 'QueueUrl' --output text)

# 3) 메인 큐에 redrive 정책을 붙여 DLQ와 연결한다(maxReceiveCount 초과 시 DLQ로 이동).
echo "[init-sqs] Attaching redrive policy (maxReceiveCount=${MAX_RECEIVE_COUNT})"
# RedrivePolicy 값 자체가 JSON 문자열(중첩 JSON)이라, CLI 축약 파서가 콤마에서 막힌다.
# 그래서 --attributes를 JSON 파일(file://)로 전달한다.
printf '{"RedrivePolicy":"{\\"deadLetterTargetArn\\":\\"%s\\",\\"maxReceiveCount\\":\\"%s\\"}"}' \
  "${DLQ_ARN}" "${MAX_RECEIVE_COUNT}" > /tmp/redrive.json

aws --endpoint-url="${ENDPOINT}" sqs set-queue-attributes \
  --queue-url "${MAIN_URL}" \
  --attributes file:///tmp/redrive.json

echo "[init-sqs] Done. main=${MAIN_QUEUE} dlq=${DLQ_QUEUE}"
