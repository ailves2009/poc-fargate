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

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
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
  description = "List of Private subnet IDs for awsvpc"
  type        = list(string)
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
