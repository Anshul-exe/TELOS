const { SQSClient, SendMessageCommand } = require("@aws-sdk/client-sqs");

// Read config from env. AWS_ENDPOINT_URL is optional and only used to point the
// SDK at a LocalStack (or other SQS-compatible) endpoint for local development.
const queueUrl = process.env.SQS_QUEUE_URL;
const endpoint = process.env.AWS_ENDPOINT_URL;

// Lazily build the client only when we actually have a queue to publish to.
const client = queueUrl
    ? new SQSClient({
          region: process.env.AWS_REGION || "ap-south-1",
          ...(endpoint ? { endpoint } : {}),
      })
    : null;

// publishEvent sends a single JSON payload to the task-events SQS queue.
// If SQS_QUEUE_URL is not configured it becomes a no-op (warns once per call)
// so the service still runs without SQS wired up (e.g. plain local dev).
module.exports.publishEvent = async (payload) => {
    if (!queueUrl) {
        console.warn(
            "SQS_QUEUE_URL not set — skipping event publish:",
            JSON.stringify(payload)
        );
        return;
    }
    try {
        await client.send(
            new SendMessageCommand({
                QueueUrl: queueUrl,
                MessageBody: JSON.stringify(payload),
            })
        );
        console.log("Published event to SQS:", JSON.stringify(payload));
    } catch (error) {
        // Do not fail the request if publishing fails; the DB write already succeeded.
        console.error("Failed to publish event to SQS:", error);
    }
};
