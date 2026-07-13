// SQS 소비 워커.
// 역할: 메인 큐를 폴링 → 메시지를 MongoDB에 적재 → 성공 시에만 큐에서 삭제.
// 처리에 실패하면 삭제하지 않아 재시도되고, maxReceiveCount(5) 초과 시 SQS가 DLQ로 격리한다.
const { receiveMessage, deleteMessage } = require("./services/sqs");
const { insertLog, closeMongo } = require("./db/mongo");

// graceful shutdown 플래그. SIGINT/SIGTERM 수신 시 false로 바꿔 폴링 루프를 멈춘다.
let isRunning = true;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// 메시지 1건 처리: 파싱 → DB 적재 → 큐에서 삭제.
// deleteMessage는 반드시 insertLog 성공 이후에만 호출한다.
// (적재 실패 시 삭제하지 않으면 메시지가 큐에 남아 재처리 → 유실 방지의 핵심)
const processMessage = async (message) => {
    const body = JSON.parse(message.Body);

    await insertLog({
        messageId: message.MessageId,
        receivedAt: body.receivedAt,
        payload: body.payload
    });

    await deleteMessage(message.ReceiptHandle);

    console.log(`Message processed: ${message.MessageId}`);
};

// 폴링 루프. long polling으로 큐를 계속 읽어 처리한다.
const startWorker = async () => {
    console.log("Log worker started.");

    while (isRunning) {
        try {
            const messages = await receiveMessage();

            // 받은 메시지가 없으면 곧바로 다음 폴링으로.
            if (messages.length === 0) {
                continue;
            }

            // 메시지별로 개별 try/catch. 한 건이 실패해도 나머지 배치 처리는 계속된다.
            // 실패한 메시지는 삭제되지 않으므로 visibility timeout 후 재처리된다.
            for (const message of messages) {
                try {
                    await processMessage(message);
                } catch (error) {
                    console.error("Failed to process message:", error);
                }
            }
        } catch (error) {
            // 폴링 자체 실패(SQS 연결 문제 등) → 잠시 쉬고 재시도해 과도한 재시도 폭주를 방지.
            console.error("Worker polling error:", error);
            await sleep(3000);
        }
    }
};

// 종료 시그널을 받으면 루프를 멈추고 MongoDB 연결을 정리한 뒤 종료한다.
const shutdown = async () => {
    console.log("Shutting down worker...");
    isRunning = false;
    await closeMongo();
    process.exit(0);
};

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);

startWorker();
