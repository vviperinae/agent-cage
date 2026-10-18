import json
import os

import boto3

iam = boto3.client("iam")
ROLE = os.environ["AGENT_ROLE_NAME"]

DENY_ALL = {
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Deny", "Action": "*", "Resource": "*"}],
}


def handler(event, context):
    detail = event.get("detail", {})
    print(json.dumps({
        "source": event.get("source"),
        "alarm": detail.get("alarmName"),
        "state": detail.get("state", {}).get("value"),
    }))
    iam.put_role_policy(
        RoleName=ROLE,
        PolicyName="CONTAINED-deny-all",
        PolicyDocument=json.dumps(DENY_ALL),
    )
    print(f"Contained role {ROLE}")
    return {"contained": ROLE}
