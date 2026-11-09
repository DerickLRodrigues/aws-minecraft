"""Controle por invocação autenticada. O alvo vem exclusivamente do Terraform."""
import os
import boto3

ec2 = boto3.client("ec2")
ssm = boto3.client("ssm")


def handler(event, context):
    action = event.get("action")
    if action not in ("start", "idle", "stop", "status"):
        raise ValueError("Ações aceitas: start, idle, stop, status")
    instance = os.environ["INSTANCE_ID"]
    info = ec2.describe_instances(InstanceIds=[instance])["Reservations"][0]["Instances"][0]
    state = info["State"]["Name"]
    result = {"action": action, "state": state, "address": info.get("PublicIpAddress")}
    if action == "start" and state == "stopped":
        ec2.start_instances(InstanceIds=[instance])
        result["state"] = "pending"
    elif action == "start" and state == "stopping":
        raise RuntimeError("Aguarde a EC2 parar e solicite a partida novamente.")
    elif action in ("idle", "stop") and state == "running":
        response = ssm.send_command(
            InstanceIds=[instance], DocumentName=os.environ["CONTROL_DOCUMENT"],
            Parameters={"mode": [action]}, TimeoutSeconds=60,
        )
        result["command_id"] = response["Command"]["CommandId"]
    print(result)
    return result
