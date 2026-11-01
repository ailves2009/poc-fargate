# Guardrails on `terraform show -json` (run by conftest in CI).
# deny = the pipeline stops; warn = shown in the PR, needs a human decision.
# These rules encode the review findings of this POC, so the same mistakes
# cannot come back unnoticed.
package main

import rego.v1

changed contains rc if {
	some rc in input.resource_changes
	not rc.change.actions == ["no-op"]
	not rc.change.actions == ["delete"]
}

as_list(x) := x if is_array(x)

as_list(x) := [x] if not is_array(x)

# IAM: no wildcard actions
deny contains msg if {
	some rc in changed
	rc.type in {"aws_iam_policy", "aws_iam_role_policy"}
	doc := json.unmarshal(rc.change.after.policy)
	some st in as_list(doc.Statement)
	st.Effect == "Allow"
	some action in as_list(st.Action)
	action == "*"
	msg := sprintf("%s: Action \"*\" is not allowed", [rc.address])
}

# Network: only 80/443 may be open to the internet
deny contains msg if {
	some rc in changed
	rc.type == "aws_vpc_security_group_ingress_rule"
	rc.change.after.cidr_ipv4 == "0.0.0.0/0"
	not rc.change.after.from_port in {80, 443}
	msg := sprintf("%s: port %v open to 0.0.0.0/0", [rc.address, rc.change.after.from_port])
}

# TLS: HTTPS listeners must use a TLS 1.2/1.3-only policy
deny contains msg if {
	some rc in changed
	rc.type == "aws_lb_listener"
	rc.change.after.protocol == "HTTPS"
	not contains(object.get(rc.change.after, "ssl_policy", ""), "TLS13")
	msg := sprintf("%s: ssl_policy must be a TLS13 policy", [rc.address])
}

# Supply chain: images pinned by digest
deny contains msg if {
	some rc in changed
	rc.type == "aws_ecs_task_definition"
	some c in json.unmarshal(rc.change.after.container_definitions)
	not contains(c.image, "@sha256:")
	msg := sprintf("%s/%s: image %s is not pinned by digest", [rc.address, c.name, c.image])
}

deny contains msg if {
	some rc in changed
	rc.type == "aws_ecs_task_definition"
	some c in json.unmarshal(rc.change.after.container_definitions)
	c.privileged == true
	msg := sprintf("%s/%s: privileged containers are not allowed", [rc.address, c.name])
}

# Known POC exceptions are warnings, not silent
warn contains msg if {
	some rc in changed
	rc.type == "aws_ecs_task_definition"
	some c in json.unmarshal(rc.change.after.container_definitions)
	not c.readonlyRootFilesystem
	msg := sprintf("%s/%s: writable root filesystem", [rc.address, c.name])
}

warn contains msg if {
	some rc in changed
	rc.type == "aws_s3_bucket"
	rc.change.after.force_destroy == true
	msg := sprintf("%s: force_destroy = true (POC only)", [rc.address])
}

# Destroying stateful resources always needs a human
warn contains msg if {
	some rc in input.resource_changes
	"delete" in rc.change.actions
	startswith(rc.type, "aws_s3_bucket")
	msg := sprintf("%s: S3 bucket will be deleted", [rc.address])
}
