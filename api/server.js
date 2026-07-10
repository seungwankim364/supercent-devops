const express = require('express');
const logsRouter = require('./routes/logs');

const app = express();
const port = process.env.PORT || 3000;

app.use(express.json({ limit: "256kb" }));

app.get("/healthz", (req, res) => {
    res.status(200).send("OK");
});

app.use("/api/v1/logs", logsRouter);

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