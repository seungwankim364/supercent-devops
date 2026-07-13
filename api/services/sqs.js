const { SQSClient, SendMessageCommand } = require("@aws-sdk/client-sqs");

// SQS 클라이언트.
// endpoint는 환경변수(SQS_ENDPOINT)로 주입한다 (로컬에서는 Endpoint를 localstack으로, AWS에서는 미설정 시 실제 SQS로 연결).
const sqsClient = new SQSClient({
    region: process.env.AWS_DEFAULT_REGION || "ap-northeast-2",
    endpoint: process.env.SQS_ENDPOINT
});

const queueUrl = process.env.SQS_QUEUE_URL;

// 메시지 1건을 SQS 메인 큐로 전송
const sendMessage = async (messageBody) => {
    // 큐 URL이 없으면 SQS 전송이 불가능하므로 에러를 던진다.
    if (!queueUrl) {
        throw new Error("SQS_QUEUE_URL cannot be empty.");
    }

    // SendMessageCommand를 생성하고 sqsClient.send()로 전송한다.
    const command = new SendMessageCommand({
        QueueUrl: queueUrl,
        MessageBody: messageBody
    });

    // SQS 전송 결과를 반환한다. 성공 시 MessageId가 포함된다.
    const data = await sqsClient.send(command);
    console.log("Message sent successfully:", data.MessageId);

    return data;
}
    
module.exports = { sendMessage };
