// 로그 수집 API 서버 진입점.
// 역할: HTTP 요청 수신 → JSON 파싱 → 라우터로 위임 → 에러 응답 표준화.
// (실제 검증/SQS 전송 로직은 routes/logs.js, services/sqs.js에 위임)
const express = require('express');
const logsRouter = require('./routes/logs');

const app = express();
const port = process.env.PORT || 3000;

// 사이즈 고정.
app.use(express.json({ limit: "256kb" }));

// 헬스체크 엔드포인트. docker-compose / ALB(target group)가 이 경로로 생존 여부를 확인 후 200 응답이 오면 정상으로 판단한다.
app.get("/healthz", (req, res) => {
    res.status(200).send("OK");
});

// 실제 로그 수신 라우트(POST /api/v1/logs).
app.use("/api/v1/logs", logsRouter);

// 전역 에러 핸들러.
// express.json()이 잘못된 JSON을 만나면 SyntaxError를 던지므로 400으로 분리 응답하고,
// 그 외 예기치 못한 에러는 500으로 처리한다.
app.use((err, req, res, next) => {
    if (err instanceof SyntaxError) {
        return res.status(400).json({ error: "Invalid JSON payload." });
    }
    console.error("Unexpected error:", err);
    res.status(500).json({ error: "Internal Server Error" });
});

app.listen(port, () => {
    console.log(`Server is running on port ${port}`);
});
