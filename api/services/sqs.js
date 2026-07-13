const { SQSClient, SendMessageCommand } = require("@aws-sdk/client-sqs");

// SQS 클라이언트.
// endpoint는 환경변수(SQS_ENDPOINT)로 주입한다.
//  - 로컬: localstack 주소를 넣어 localstack의 가짜 SQS로 연결
//  - AWS 운영: SQS_ENDPOINT를 비우면 SDK가 리전 기본 AWS SQS 엔드포인트로 붙는다
//    (즉 환경변수만 바꾸면 코드 수정 없이 로컬↔AWS 전환)
const sqsClient = new SQSClient({
    region: process.env.AWS_DEFAULT_REGION || "ap-northeast-2",
    endpoint: process.env.SQS_ENDPOINT
});

const queueUrl = process.env.SQS_QUEUE_URL;

// 메시지 1건을 SQS 메인 큐로 전송한다.
const sendMessage = async (messageBody) => {
    // 큐 URL이 없으면 조용히 성공한 것처럼 보이지 않도록 즉시 에러를 던진다.
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
