#!/usr/bin/env python3
"""Turn `terraform show -json` into facts for reviewers (human and AI).

Everything here is deterministic. The AI reviewer only explains these facts;
it never decides whether security approval is required. That decision is
made by the rules below, so it cannot be talked out of it by a prompt.

Usage: plan_facts.py plan.json [checkov.json] [infracost.json] > facts.json
"""

import json
import sys

# Changes to these resource types need a security reviewer, whatever the diff.
SECURITY_TYPES = (
    "aws_iam_", "aws_kms_", "aws_security_group", "aws_vpc_security_group_",
    "aws_lb_listener", "aws_acm_", "aws_route53_record", "aws_s3_bucket_policy",
    "aws_s3_bucket_public_access_block", "aws_lambda_permission",
    "aws_secretsmanager_", "aws_wafv2_", "aws_cloudtrail", "aws_ecs_cluster",
)
# Losing these loses data or history: deleting/replacing them needs approval.
STATEFUL_TYPES = (
    "aws_s3_bucket", "aws_cloudwatch_log_group", "aws_kms_key",
    "aws_kinesis_firehose_delivery_stream", "aws_db_", "aws_rds_",
)
# What users notice first when it breaks.
USER_FACING_TYPES = ("aws_lb", "aws_route53_record", "aws_ecs_service", "aws_acm_")
PUBLIC_PORTS = {80, 443}
# Actions without resource-level permissions: "*" is the only valid Resource.
NO_RESOURCE_LEVEL = {
    "ecr:GetAuthorizationToken", "logs:DescribeLogGroups",
    "ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel",
    "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel",
}


def action_of(change):
    actions = change["actions"]
    if actions == ["no-op"] or actions == ["read"]:
        return None
    if "delete" in actions and "create" in actions:
        return "replace"
    return actions[0]


def policy_findings(address, policy):
    """Flag wildcard actions in IAM policy documents known at plan time."""
    findings = []
    try:
        doc = json.loads(policy)
    except (TypeError, ValueError):
        return findings  # unknown until apply: covered by the type rule
    statements = doc.get("Statement", [])
    if isinstance(statements, dict):
        statements = [statements]
    for st in statements:
        if st.get("Effect") != "Allow":
            continue
        actions = st.get("Action", [])
        actions = [actions] if isinstance(actions, str) else actions
        resources = st.get("Resource", [])
        resources = [resources] if isinstance(resources, str) else resources
        if any(a == "*" or a.endswith(":*") for a in actions):
            findings.append(f"{address}: wildcard action {actions}")
        if "*" in resources and not all(a in NO_RESOURCE_LEVEL for a in actions):
            findings.append(f"{address}: Resource \"*\" for {actions}")
    return findings


def container_findings(address, container_json):
    findings = []
    try:
        containers = json.loads(container_json)
    except (TypeError, ValueError):
        return findings
    for c in containers:
        name = c.get("name")
        if "@sha256:" not in c.get("image", ""):
            findings.append(f"{address}/{name}: image not pinned by digest")
        if c.get("privileged"):
            findings.append(f"{address}/{name}: privileged container")
        if not c.get("readonlyRootFilesystem"):
            findings.append(f"{address}/{name}: writable root filesystem")
    return findings


def main():
    plan = json.load(open(sys.argv[1]))
    checkov = json.load(open(sys.argv[2])) if len(sys.argv) > 2 else None
    infracost = json.load(open(sys.argv[3])) if len(sys.argv) > 3 else None

    changes = {"create": [], "update": [], "replace": [], "delete": []}
    security_changes, findings, reasons = [], [], []
    stateful_loss, user_facing = [], []

    for rc in plan.get("resource_changes", []):
        act = action_of(rc["change"])
        if not act:
            continue
        addr, rtype = rc["address"], rc["type"]
        after = rc["change"].get("after") or {}
        changes[act].append(addr)

        if rtype.startswith(SECURITY_TYPES):
            security_changes.append(f"{act} {addr}")
        if act in ("delete", "replace") and rtype.startswith(STATEFUL_TYPES):
            stateful_loss.append(f"{act} {addr}")
        if act in ("delete", "replace", "update") and rtype.startswith(USER_FACING_TYPES):
            user_facing.append(f"{act} {addr}")

        if rtype in ("aws_iam_policy", "aws_iam_role_policy"):
            findings += policy_findings(addr, after.get("policy"))
        if rtype == "aws_vpc_security_group_ingress_rule":
            if after.get("cidr_ipv4") == "0.0.0.0/0" and after.get("from_port") not in PUBLIC_PORTS:
                findings.append(f"{addr}: port {after.get('from_port')} open to 0.0.0.0/0")
        if rtype == "aws_lb_listener" and after.get("protocol") == "HTTPS":
            if "TLS13" not in (after.get("ssl_policy") or ""):
                findings.append(f"{addr}: ssl_policy {after.get('ssl_policy')} allows legacy TLS")
        if rtype == "aws_ecs_task_definition":
            findings += container_findings(addr, after.get("container_definitions"))

    if security_changes:
        reasons.append(f"{len(security_changes)} change(s) to IAM/network/TLS/DNS resources")
    if findings:
        reasons.append(f"{len(findings)} policy finding(s)")
    if stateful_loss:
        reasons.append(f"{len(stateful_loss)} stateful resource(s) deleted or replaced")

    failed_checks = []
    if checkov:
        reports = checkov if isinstance(checkov, list) else [checkov]
        for rep in reports:
            for f in rep.get("results", {}).get("failed_checks", []):
                failed_checks.append(f"{f['check_id']} {f['resource']}: {f['check_name']}")
    if failed_checks:
        reasons.append(f"{len(failed_checks)} failed Checkov check(s)")

    cost = None
    if infracost:
        cost = {
            "currency": infracost.get("currency", "USD"),
            "past_monthly": infracost.get("pastTotalMonthlyCost"),
            "monthly": infracost.get("totalMonthlyCost"),
            "diff_monthly": infracost.get("diffTotalMonthlyCost"),
        }

    json.dump({
        "summary": {k: len(v) for k, v in changes.items()},
        "changes": changes,
        "blast_radius": {
            "replaced_or_deleted": changes["replace"] + changes["delete"],
            "stateful_loss": stateful_loss,
            "user_facing": user_facing,
        },
        "security": {
            "approval_required": bool(reasons),
            "reasons": reasons,
            "changes": security_changes,
            "findings": findings,
            "checkov_failed": failed_checks[:50],
        },
        "cost": cost,
    }, sys.stdout, indent=2)


if __name__ == "__main__":
    main()
