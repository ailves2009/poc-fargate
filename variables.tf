# poc-fargate/variables.tf

variable "region" {
  description = "AWS region for deploying resources"
  type        = string
}

variable "account_id" {
  description = "AWS account ID the provider is pinned to (allowed_account_ids). Set it only in the gitignored inputs.tfvars"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "dns_account_id" {
  description = "Account that owns hosted_zone_id, if different from account_id (DNS in a shared account)"
  type        = string
  default     = null

  validation {
    condition     = var.dns_account_id == null || can(regex("^[0-9]{12}$", var.dns_account_id))
    error_message = "dns_account_id must be a 12-digit AWS account ID."
  }
}

variable "dns_aws_profile" {
  description = "AWS CLI profile for the DNS account (local runs only; null = default credential chain)"
  type        = string
  default     = null
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC (ALB egress is limited to it)"
  type        = string
}

variable "name" {
  description = "Name of the service / family for the ECS task"
  type        = string
}

variable "domain_name" {
  description = "Domain name for the ACM certificate"
  type        = string
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone ID for the domain_name"
  type        = string
}

variable "create_acm_certificate" {
  description = "Whether to create an ACM certificate for the domain name"
  type        = bool
  default     = false
}

variable "acm_certificate_arn" {
  description = "ARN of existing ACM certificate (use when create_acm_certificate=false)"
  type        = string
  default     = ""
}

variable "enable_alb" {
  description = "Whether to create an Application Load Balancer"
  type        = bool
  default     = true
}

variable "poc_container_port" {
  description = "Port inside the POC app container"
  type        = number
}

variable "app_container_port" {
  description = "Port inside the app container"
  type        = number
}

variable "fluent_bit_image" {
  description = "Docker image for Fluent Bit sidecar container, pinned by digest (<repo>@sha256:<64 hex>)"
  type        = string

  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.fluent_bit_image))
    error_message = "Pin the image by digest: <repo>@sha256:<digest>. Mutable tags such as :latest or :stable are not allowed."
  }
}

variable "poc_app_image" {
  description = "Docker image for POC app ECS task, pinned by digest (<repo>@sha256:<64 hex>)"
  type        = string

  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.poc_app_image))
    error_message = "Pin the image by digest: <repo>@sha256:<digest>. Mutable tags such as :latest or :stable are not allowed."
  }
}

variable "nginx_image" {
  description = "Unprivileged nginx image (UID 101, listens on 8080), pinned by digest (<repo>@sha256:<64 hex>)"
  type        = string

  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.nginx_image))
    error_message = "Pin the image by digest: <repo>@sha256:<digest>. Mutable tags such as :latest or :stable are not allowed."
  }
}

variable "poc_app_cpu" {
  description = "CPU units for POC app container (as string)"
  type        = string
  default     = "256"
}

variable "service_cpu" {
  description = "CPU units for the ECS service (as string)"
  type        = string
  default     = "512"
}

variable "fluent_bit_cpu" {
  description = "CPU units for Fluent Bit sidecar container (as string)"
  type        = string
  default     = "128"
}

variable "nginx_cpu" {
  description = "CPU units for app container (as string)"
  type        = string
  default     = "512"
}

variable "service_memory" {
  description = "Memory (MB) for the ECS service (as string)"
  type        = string
  default     = "512"
}
variable "poc_app_memory" {
  description = "Memory (MB) for POC app container (as string)"
  type        = string
  default     = "512"
}

variable "fluent_bit_memory" {
  description = "Memory (MB) for Fluent Bit sidecar container (as string)"
  type        = string
  default     = "256"
}

variable "nginx_memory" {
  description = "Memory (MB) for app container (as string)"
  type        = string
  default     = "1024"
}

variable "desired_count" {
  description = "Initial task count per service; also the autoscaling minimum"
  type        = number
  default     = 2
}

variable "autoscaling_max_capacity" {
  description = "Maximum task count per service for target-tracking autoscaling"
  type        = number
  default     = 10
}

variable "blue_green_bake_time_minutes" {
  description = "How long ECS keeps the previous (blue) tasks after shifting production traffic, for instant rollback"
  type        = number
  default     = 5
}

variable "public_subnets" {
  description = "List of Public subnet IDs for awsvpc"
  type        = list(string)
}

variable "private_subnets" {
  description = "Subnets for the ECS tasks. Private subnets need a NAT gateway or VPC endpoints to pull images"
  type        = list(string)
}

variable "assign_public_ip" {
  description = "Give tasks a public IP so they can pull images without a NAT gateway (POC on a default VPC). Inbound traffic is still limited to the ALB security group"
  type        = bool
  default     = false
}

variable "smoke_test_path" {
  description = "Path the blue/green lifecycle hook requests through the test listener rule before production traffic is shifted"
  type        = string
  default     = "/"
}

variable "alarm_5xx_threshold" {
  description = "Target 5xx responses per minute that trip the deployment alarm and roll back a blue/green deployment"
  type        = number
  default     = 5
}

variable "log_retention" {
  description = "Retention for CloudWatch logs (days)"
  type        = number
  default     = 7
}

variable "vpc_id" {
  description = "VPC ID required for creating the target group and security groups"
  type        = string
  default     = ""
}

variable "service_names" {
  type    = list(string)
  default = ["poc-ecs-service", "poc-ecs-service-rc"]
}
