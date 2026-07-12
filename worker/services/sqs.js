const {
    SQSClient,
    ReceiveMessageCommand,
    DeleteMessageCommand
} = require("@aws-sdk/client-sqs");

const sqsClient = new SQSClient({
    region: process.env.AWS_DEFAULT_REGION || "ap-northeast-2",
    endpoint: process.env.SQS_ENDPOINT
});

const queueUrl = process.env.SQS_QUEUE_URL;

const receiveMessage = async () => {
    if (!queueUrl) {
        throw new Error("SQS_QUEUE_URL cannot be empty.");
    }

    const command = new ReceiveMessageCommand({
        QueueUrl: queueUrl,
        MaxNumberOfMessages: 10,
        WaitTimeSeconds: 10,
        VisibilityTimeout: 30
    });

    const result = await sqsClient.send(command);

    return result.Messages || [];
};

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