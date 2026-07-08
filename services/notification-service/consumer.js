const {
    SQSClient,
    ReceiveMessageCommand,
    DeleteMessageCommand,
} = require("@aws-sdk/client-sqs");
const Notification = require("./models/notification");

// Config mirrors task-service's sqs.js. AWS_ENDPOINT_URL is optional and only
// used to point the SDK at a LocalStack (or other SQS-compatible) endpoint for
// local development.
const queueUrl = process.env.SQS_QUEUE_URL;
const endpoint = process.env.AWS_ENDPOINT_URL;

const POLL_INTERVAL_MS = 5000;

const client = queueUrl
    ? new SQSClient({
          region: process.env.AWS_REGION || "ap-south-1",
          ...(endpoint ? { endpoint } : {}),
      })
    : null;

// Handles a single SQS message: parse -> persist a Notification -> delete.
// On parse/save failure we log and DO NOT delete, so the message returns to the
// queue after its visibility timeout for a later retry.
async function handleMessage(message) {
    let payload;
    try {
        payload = JSON.parse(message.Body);
    } catch (error) {
        console.error("Failed to parse message body, leaving on queue:", error);
        return;
    }

    const { taskId, event } = payload;

    try {
        await new Notification({
            taskId,
            event,
            message: `Task ${taskId} was ${event}`,
        }).save();
        console.log(`Recorded notification: Task ${taskId} was ${event}`);
    } catch (error) {
        console.error(
            "Failed to save notification, leaving message on queue:",
            error
        );
        return;
    }

    try {
        await client.send(
            new DeleteMessageCommand({
                QueueUrl: queueUrl,
                ReceiptHandle: message.ReceiptHandle,
            })
        );
    } catch (error) {
        // The record is already saved; a delete failure just means the message
        // may be redelivered (and safely re-recorded) later.
        console.error("Failed to delete message from queue:", error);
    }
}

async function pollOnce() {
    const response = await client.send(
        new ReceiveMessageCommand({
            QueueUrl: queueUrl,
            MaxNumberOfMessages: 10,
            WaitTimeSeconds: 5,
        })
    );
    const messages = response.Messages || [];
    for (const message of messages) {
        await handleMessage(message);
    }
}

// Starts the recursive long-poll loop. No-ops (with a warning) when SQS is not
// configured, so the service still runs for local/manual use without a queue.
function startConsumer() {
    if (!queueUrl) {
        console.warn(
            "SQS_QUEUE_URL not set — notification consumer will not start."
        );
        return;
    }

    console.log("Starting SQS consumer loop:", queueUrl);
    const loop = async () => {
        try {
            await pollOnce();
        } catch (error) {
            console.error("Error while polling SQS:", error);
        }
        setTimeout(loop, POLL_INTERVAL_MS);
    };
    loop();
}

module.exports = { startConsumer };
