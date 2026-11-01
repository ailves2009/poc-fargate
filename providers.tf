# poc-fargate/providers.tf

provider "aws" {
  region = var.region

  # A wrong AWS profile fails at plan time instead of creating resources
  # in another account. The real ID lives only in the gitignored inputs.tfvars.
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = local.default_tags
  }
}

# Route53 records (service alias, ACM validation) go to the account that owns
# the parent zone. Typical multi-account layout: DNS lives in a shared
# account, workloads in their own. Without dns_* overrides it is the same
# account and the same credentials as the default provider.
provider "aws" {
  alias   = "dns"
  region  = var.region
  profile = var.dns_aws_profile

  allowed_account_ids = [coalesce(var.dns_account_id, var.account_id)]

  default_tags {
    tags = local.default_tags
  }
}

locals {
  default_tags = {
    Environment = "plt"
    Client      = "poc"
    Project     = "poc-fargate"
    Managed     = "terraform"
  }
}

terraform {
  required_version = ">= 1.10"

  # Partial configuration: bucket and region come from the gitignored
  # backend.hcl (see backend.hcl.example), so the bucket name, which embeds
  # the account ID, stays out of the public repo.
  #   terraform init -backend-config=backend.hcl
  # use_lockfile = S3-native state locking (Terraform >= 1.10), no DynamoDB.
  backend "s3" {
    key          = "poc-fargate/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.28.0, < 7.0.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}
