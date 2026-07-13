const {
    SQSClient,
    ReceiveMessageCommand,
    DeleteMessageCommand
} = require("@aws-sdk/client-sqs");

// SQS 클라이언트. endpoint는 SQS_ENDPOINT로 주입(로컬=localstack / AWS=미설정 시 실제 SQS).
const sqsClient = new SQSClient({
    region: process.env.AWS_DEFAULT_REGION || "ap-northeast-2",
    endpoint: process.env.SQS_ENDPOINT
});

const queueUrl = process.env.SQS_QUEUE_URL;

// 메인 큐에서 메시지를 수신한다.
const receiveMessage = async () => {
    if (!queueUrl) {
        throw new Error("SQS_QUEUE_URL cannot be empty.");
    }

    const command = new ReceiveMessageCommand({
        QueueUrl: queueUrl,
        MaxNumberOfMessages: 10,   // 한 번에 최대 10건까지 배치 수신(처리량 향상)
        WaitTimeSeconds: 10,       // long polling: 메시지가 없으면 최대 10초 대기(빈 폴링/비용 절감)
        VisibilityTimeout: 30      // 수신 후 30초간 다른 워커에게 안 보임. 그 안에 삭제 못하면 재처리 대상이 됨
    });

    const result = await sqsClient.send(command);

    // 메시지가 없으면 Messages가 undefined이므로 빈 배열로 정규화.
    return result.Messages || [];
};

// 처리에 성공한 메시지를 큐에서 삭제한다(ReceiptHandle로 지정).
// 삭제하지 않으면 visibility timeout 후 다시 수신되어 재처리된다.
const deleteMessage = async (receiptHandle) => {
    if (!queueUrl) {
        throw new Error("SQS_QUEUE_URL cannot be empty.");
    }

    const command = new DeleteMessageCommand({
        QueueUrl: queueUrl,
        ReceiptHandle: receiptHandle
    });

    return sqsClient.send(command);
};

module.exports = {
    receiveMessage,
    deleteMessage
};
