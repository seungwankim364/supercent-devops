const { receiveMessage, deleteMessage } = require("./services/sqs");
  const { insertLog, closeMongo } = require("./db/mongo");

  let isRunning = true;

  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

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

  const startWorker = async () => {
    console.log("Log worker started.");

    while (isRunning) {
      try {
        const messages = await receiveMessage();

        if (messages.length === 0) {
          continue;
        }

        for (const message of messages) {
          try {
            await processMessage(message);
          } catch (error) {
            console.error("Failed to process message:", error);
          }
        }
      } catch (error) {
        console.error("Worker polling error:", error);
        await sleep(3000);
      }
    }
  };

  const shutdown = async () => {
    console.log("Shutting down worker...");
    isRunning = false;
    await closeMongo();
    process.exit(0);
  };

  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);

  startWorker();