const { SQSClient, SendMessageCommand } = require("@aws-sdk/client-sqs");

const sqsClient = new SQSClient({
    region: process.env.AWS_DEFAULT_REGION || "ap-northeast-2",
    endpoint: process.env.SQS_ENDPOINT
});

const queueUrl = process.env.SQS_QUEUE_URL;

const sendMessage = async (messageBody) => {
    if (!queueUrl) {
        throw new Error("SQS_QUEUE_URL cannot be empty.");
    }

    const command = new SendMessageCommand({
        QueueUrl: queueUrl,
        MessageBody: messageBody
    });

    const data = await sqsClient.send(command);
    console.log("Message sent successfully:", data.MessageId);

    return data;
}
   
    
module.exports = { sendMessage };