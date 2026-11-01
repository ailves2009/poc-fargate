# poc-fargate/providers.tf

provider "aws" {
  region = var.region

  # A wrong AWS profile fails at plan time instead of creating resources
  # in another account. The real ID lives only in the gitignored inputs.tfvars.
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Environment = "plt"
      Client      = "poc"
      Project     = "poc-fargate"
      Managed     = "terraform"
    }
  }
}

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.28.0, < 7.0.0"
    }
  }
}
