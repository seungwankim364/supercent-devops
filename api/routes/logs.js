const express = require("express");
const router = express.Router();
const { sendMessage } = require("../services/sqs");

router.post("/", async (req, res) => {
    try {
        const logData = req.body;

        if (!logData || typeof logData !== "object" || Array.isArray(logData)) {
            return res.status(400).json({ error: "Invalid log data. It should be a JSON object."
        });
        }

        const messageBody = JSON.stringify(({
            receivedAt: new Date().toISOString(),
            payload: logData
        }));

        const result = await sendMessage(messageBody);

        return res.status(200).json({
            message: "Log data sent to SQS successfully.",
            messageId: result.MessageId
        });
    } catch (error) {
        console.error("Error sending log data to SQS:", error);
        return res.status(500).json({ 
            error: "Failed to send log data to SQS." 
        });
    }
});

module.exports = router;
        
    