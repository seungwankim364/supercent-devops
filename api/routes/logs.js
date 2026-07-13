const express = require("express");
const router = express.Router();
const { sendMessage } = require("../services/sqs");

// POST /api/v1/logs
// 클라이언트가 보낸 인게임 로그를 받아 검증 후 SQS로 전송
// 여기서는 DB에 직접 쓰지 않고 큐에 넣기만 하고 즉시 200 응답 (디커플링).
// API 응답 시간이 DB 처리 속도에 묶이지 않고, 트래픽 급증은 SQS가 흡수한다.
router.post("/", async (req, res) => {
    try {
        const logData = req.body;

        // JSON 객체만 허용(null / 배열 / 원시값은 거부).
        if (!logData || typeof logData !== "object" || Array.isArray(logData)) {
            return res.status(400).json({ error: "Invalid log data. It should be a JSON object."
        });
        }

        // 원본 로그를 payload로 코딩.
        // 이 구조는 worker가 그대로 파싱해 MongoDB에 저장한다.
        const messageBody = JSON.stringify(({
            receivedAt: new Date().toISOString(),
            payload: logData
        }));

        const result = await sendMessage(messageBody);

        // SQS 전송 성공하면 메시지 ID를 돌려주며 200 응답.
        return res.status(200).json({
            message: "Log data sent to SQS successfully.",
            messageId: result.MessageId
        });
    } catch (error) {
        // SQS 전송 실패 시 500 응답 (응답 안 될시 DLQ로 격리)
        console.error("Error sending log data to SQS:", error);
        return res.status(500).json({
            error: "Failed to send log data to SQS."
        });
    }
});

module.exports = router;
