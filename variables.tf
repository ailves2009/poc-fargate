# poc-fargate/variables.tf

variable "region" {
  description = "AWS region for deploying resources"
  type        = string
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
  description = "Docker image for Fluent Bit sidecar container"
  type        = string
}

variable "poc_app_image" {
  description = "Docker image for POC app ECS task"
  type        = string
}

variable "nginx_image" {
  description = "Docker image for app ECS task"
  type        = string
}

variable "external_port" {
  description = "External port for accessing the service (through ALB)"
  type        = number
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
  default     = "512"
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
  default     = "1024"
}

variable "nginx_memory" {
  description = "Memory (MB) for app container (as string)"
  type        = string
  default     = "1024"
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "public_subnets" {
  description = "List of Public subnet IDs for awsvpc"
  type        = list(string)
}

variable "private_subnets" {
  description = "List of Private subnet IDs for awsvpc"
  type        = list(string)
}

variable "sg_description" {
  description = "Description of the security group"
  type        = string
  default     = "Security group for ECS Fargate tasks"
}

variable "sg_ssh_port" {
  description = "Port for SSH access"
  type        = number
  default     = 22
}

variable "ssh_cidr_blocks" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "environment" {
  description = "Map of environment variables for the container"
  type        = map(string)
  default     = {}
}

variable "log_group_name" {
  description = "Optional name of the log group"
  type        = string
  default     = ""
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

variable "health_check_path" {
  description = "Path for the health check of the target group"
  type        = string
  default     = "/health"
}

variable "deployment_minimum_healthy_percent" {
  type    = number
  default = 50
}

variable "deployment_maximum_percent" {
  type    = number
  default = 200
}

variable "route_table_ids" {
  description = "Optional list of route table IDs for S3 gateway endpoint (provide to create S3 endpoint)."
  type        = list(string)
  default     = []
}

variable "certificate_arn" {
  description = "Optional certificate ARN for HTTPS listener. If empty, HTTPS listener won't be created."
  type        = string
  default     = ""
}

variable "service_names" {
  type    = list(string)
  default = ["poc-ecs-service", "poc-ecs-service-rc"]
}
