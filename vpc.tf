# poc-fargate/vpc.tf

# Same network layout as the EKS POCs of the series (terraform-aws-modules/vpc
# 6.6.0, 3 AZs, /20 private + /24 public, one NAT, flow logs), with its own
# CIDR so the POCs can later be peered or attached to a Transit Gateway.

data "aws_availability_zones" "available" {
  # Regular AZs only, no Local Zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.0"

  name = local.name
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = [for k, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]

  # POC cost trade-off: one NAT for all AZs (an AZ outage cuts task egress)
  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false
  enable_dns_hostnames   = true

  enable_flow_log                                 = true
  create_flow_log_cloudwatch_log_group            = true
  create_flow_log_cloudwatch_iam_role             = true
  flow_log_max_aggregation_interval               = 60
  flow_log_cloudwatch_log_group_retention_in_days = 30

  tags = local.tags
}
