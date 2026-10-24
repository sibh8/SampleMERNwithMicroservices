"""
AWS Lambda that forwards SNS messages to a Slack (or Microsoft Teams) channel.

Trigger: SNS topic subscription (the mern-deployments topic).
Env var: SLACK_WEBHOOK_URL  - an incoming webhook URL from Slack or Teams.

Both Slack and Teams incoming webhooks accept a JSON body with a "text" field,
so the same payload works for either platform.
"""
import json
import os
import urllib.request


def _format(record):
    """Turn one SNS record into a readable chat line."""
    sns = record.get("Sns", {})
    subject = sns.get("Subject") or "AWS Notification"
    message = sns.get("Message", "")

    # CloudWatch alarm messages arrive as JSON; summarize them nicely.
    try:
        alarm = json.loads(message)
        if "AlarmName" in alarm:
            state = alarm.get("NewStateValue", "UNKNOWN")
            reason = alarm.get("NewStateReason", "")
            emoji = ":rotating_light:" if state == "ALARM" else ":white_check_mark:"
            return f"{emoji} *{alarm['AlarmName']}* -> {state}\n{reason}"
    except (ValueError, TypeError):
        pass

    return f"*{subject}*\n{message}"


def handler(event, context):
    webhook = os.environ.get("SLACK_WEBHOOK_URL")
    if not webhook:
        raise RuntimeError("SLACK_WEBHOOK_URL environment variable is not set")

    lines = [_format(r) for r in event.get("Records", [])]
    text = "\n\n".join(lines) if lines else "Empty SNS event"

    payload = json.dumps({"text": text}).encode("utf-8")
    req = urllib.request.Request(
        webhook,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        status = resp.status

    return {"statusCode": status, "forwarded": len(lines)}
