# poc-fargate/main.tf

# ECS Fargate cluster with two services:
# - poc-ecs-service-rc: public nginx behind the ALB, ECS-native blue/green
#   deployments (blue-tg / green-tg), target-tracking autoscaling.
# - poc-ecs-service: internal sample app (Service Connect only) that ships its
#   logs through a FireLens (Fluent Bit) sidecar to Kinesis Firehose -> S3.

locals {
  region = var.region
  name   = var.name

  poc_container_name = "poc-ecs-app"
  app_container_name = "nginx"
  poc_container_port = var.poc_container_port
  app_container_port = var.app_container_port

  tags = {
    Name       = local.name
    Repository = "https://github.com/ailves2009/poc-fargate"
  }

  # On-Demand baseline, the rest split 1:1 with Spot. The cluster default is
  # not enough: a service without its own strategy gets launch_type = FARGATE
  # and never uses Spot.
  capacity_provider_strategy = {
    fargate = {
      capacity_provider = "FARGATE"
      base              = 1
      weight            = 1
    }
    fargate_spot = {
      capacity_provider = "FARGATE_SPOT"
      weight            = 1
    }
  }

  # Application Auto Scaling, the ECS counterpart of HPA in the EKS POCs
  autoscaling_policies = {
    cpu = {
      policy_type = "TargetTrackingScaling"
      target_tracking_scaling_policy_configuration = {
        predefined_metric_specification = {
          predefined_metric_type = "ECSServiceAverageCPUUtilization"
        }
        target_value       = 70
        scale_out_cooldown = 60
        scale_in_cooldown  = 300
      }
    }
  }
}

################################################################################
# CloudWatch Log Groups
################################################################################

# Container log groups (/aws/ecs/<service>/<container>) are created by the
# ecs module itself; their retention is set per container below.

# ECS Exec session audit log
resource "aws_cloudwatch_log_group" "ecs_exec" {
  name              = "/aws/ecs/ecs-integrated/exec"
  retention_in_days = var.log_retention
  tags              = local.tags
}

################################################################################
# Cluster
################################################################################

module "ecs" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "~> 7.0"

  cluster_name = "ecs-integrated"

  # Every ECS Exec session (who, which task, every command and its output)
  # is recorded in CloudWatch, so interactive access to a task is auditable.
  cluster_configuration = {
    execute_command_configuration = {
      logging = "OVERRIDE"
      log_configuration = {
        cloud_watch_log_group_name = aws_cloudwatch_log_group.ecs_exec.name
      }
    }
  }

  cluster_capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  default_capacity_provider_strategy = {
    FARGATE = {
      base   = 1
      weight = 1
    }
    FARGATE_SPOT = {
      weight = 1
    }
  }

  services = {
    # Internal sample app: no ALB, reachable only through Service Connect.
    # Its job in this POC is to show FireLens -> Firehose -> S3 log shipping.
    poc-ecs-service = {
      enable_execute_command     = true
      cpu                        = var.service_cpu
      memory                     = var.service_memory
      desired_count              = var.desired_count
      capacity_provider_strategy = local.capacity_provider_strategy

      autoscaling_min_capacity = var.desired_count
      autoscaling_max_capacity = var.autoscaling_max_capacity
      autoscaling_policies     = local.autoscaling_policies

      deployment_circuit_breaker = {
        enable   = true
        rollback = true
      }

      # The module's default exec policy grants logs/ECR on "*";
      # aws_iam_policy.task_exec below is the scoped replacement.
      create_task_exec_policy = false

      container_definitions = {
        # FireLens log router. ECS generates its Fluent Bit config from the
        # app container's logConfiguration options below; on Fargate a custom
        # config can only be baked into the image (config-file-type = file).
        fluent-bit = {
          cpu                                    = var.fluent_bit_cpu
          memory                                 = var.fluent_bit_memory
          essential                              = true
          image                                  = var.fluent_bit_image
          cloudwatch_log_group_retention_in_days = var.log_retention
          memoryReservation                      = 50
          firelensConfiguration = {
            type = "fluentbit"
          }
        }

        poc-ecs-app = {
          cpu                                    = var.poc_app_cpu
          memory                                 = var.poc_app_memory
          essential                              = true
          image                                  = var.poc_app_image
          cloudwatch_log_group_retention_in_days = var.log_retention
          memoryReservation                      = 100
          portMappings = [
            {
              name          = local.poc_container_name
              containerPort = local.poc_container_port
              protocol      = "tcp"
            }
          ]
          healthCheck = {
            command     = ["CMD-SHELL", "curl -f http://localhost:${local.poc_container_port}/ || exit 1"]
            interval    = 30
            timeout     = 5
            retries     = 3
            startPeriod = 60
          }

          # Example image used requires access to write to root filesystem
          readonlyRootFilesystem = false

          dependsOn = [{
            containerName = "fluent-bit"
            condition     = "START"
          }]

          # stdout/stderr -> FireLens -> Fluent Bit kinesis_firehose output
          logConfiguration = {
            logDriver = "awsfirelens"
            options = {
              Name                    = "kinesis_firehose"
              region                  = local.region
              delivery_stream         = aws_kinesis_firehose_delivery_stream.firehose_stream.name
              log-driver-buffer-limit = "2097152"
            }
          }
        }
      }

      service_connect_configuration = {
        namespace = aws_service_discovery_http_namespace.this.name
        service = [{
          client_alias = {
            port     = local.poc_container_port
            dns_name = local.poc_container_name
          }
          port_name      = local.poc_container_name
          discovery_name = local.poc_container_name
        }]
      }

      subnet_ids = var.private_subnets

      security_group_egress_rules = {
        all = {
          ip_protocol = "-1"
          cidr_ipv4   = "0.0.0.0/0"
        }
      }
    }

    # Public nginx with ECS-native blue/green: a new revision starts in the
    # idle target group, gets test traffic first, then ECS shifts production
    # traffic and keeps the old tasks for the bake time (instant rollback).
    poc-ecs-service-rc = {
      enable_execute_command     = true
      cpu                        = var.service_cpu
      memory                     = var.service_memory
      desired_count              = var.desired_count
      capacity_provider_strategy = local.capacity_provider_strategy

      autoscaling_min_capacity = var.desired_count
      autoscaling_max_capacity = var.autoscaling_max_capacity
      autoscaling_policies     = local.autoscaling_policies

      deployment_configuration = var.enable_alb ? {
        strategy             = "BLUE_GREEN"
        bake_time_in_minutes = tostring(var.blue_green_bake_time_minutes)
      } : null

      deployment_circuit_breaker = {
        enable   = true
        rollback = true
      }

      create_task_exec_policy = false

      # Task-local scratch space (Fargate ephemeral storage) for nginx,
      # so its root filesystem can stay read-only.
      volume = {
        tmp = {}
      }

      container_definitions = {
        nginx = {
          cpu                                    = var.nginx_cpu
          memory                                 = var.nginx_memory
          essential                              = true
          image                                  = var.nginx_image
          cloudwatch_log_group_retention_in_days = var.log_retention
          memoryReservation                      = 100
          portMappings = [
            {
              name          = local.app_container_name
              containerPort = local.app_container_port
              protocol      = "tcp"
            }
          ]
          healthCheck = {
            command     = ["CMD-SHELL", "wget -q --spider http://localhost:${local.app_container_port}/ || exit 1"]
            interval    = 30
            timeout     = 5
            retries     = 3
            startPeriod = 60
          }

          # awslogs to the module-managed group /aws/ecs/poc-ecs-service-rc/nginx
          enable_cloudwatch_logging = true

          # Same hardening as the EKS POCs (Pod Security "restricted"):
          # unprivileged nginx image (UID 101, listens on 8080), read-only
          # root filesystem with a writable /tmp, and no Linux capabilities.
          user                   = "101:101"
          readonlyRootFilesystem = true
          linuxParameters = {
            capabilities = {
              drop = ["ALL"]
            }
          }
          mountPoints = [{
            sourceVolume  = "tmp"
            containerPath = "/tmp"
            readOnly      = false
          }]
        }
      }

      service_connect_configuration = {
        namespace = aws_service_discovery_http_namespace.this.name
        service = [{
          client_alias = {
            port     = local.app_container_port
            dns_name = local.app_container_name
          }
          port_name      = local.app_container_name
          discovery_name = local.app_container_name
        }]
      }

      load_balancer = var.enable_alb ? {
        service = {
          target_group_arn = module.alb[0].target_groups["blue-tg"].arn
          container_name   = local.app_container_name
          container_port   = local.app_container_port

          advanced_configuration = {
            alternate_target_group_arn = module.alb[0].target_groups["green-tg"].arn
            production_listener_rule   = aws_lb_listener_rule.production[0].arn
            test_listener_rule         = aws_lb_listener_rule.test[0].arn
          }
        }
      } : {}

      subnet_ids = var.private_subnets

      security_group_ingress_rules = var.enable_alb ? {
        alb = {
          description                  = "nginx from the ALB only"
          from_port                    = local.app_container_port
          to_port                      = local.app_container_port
          ip_protocol                  = "tcp"
          referenced_security_group_id = module.alb[0].security_group_id
        }
      } : {}
      security_group_egress_rules = {
        all = {
          ip_protocol = "-1"
          cidr_ipv4   = "0.0.0.0/0"
        }
      }
    }
  }

  tags = local.tags
}

################################################################################
# Supporting Resources (ALB, DNS)
################################################################################
resource "aws_service_discovery_http_namespace" "this" {
  name        = local.name
  description = "CloudMap namespace for ${local.name}"
  tags        = local.tags
}

module "alb" {
  count   = var.enable_alb ? 1 : 0
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 10.0"

  name               = local.name
  load_balancer_type = "application"
  internal           = false
  vpc_id             = var.vpc_id
  subnets            = var.public_subnets

  # For poc only
  enable_deletion_protection = false

  # Security Group
  security_group_ingress_rules = {
    all_http = {
      description = "SG ALB module - all_http"
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    }
    all_https = {
      description = "SG ALB module - all_https"
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }
  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = var.vpc_cidr
    }
  }

  listeners = {
    alb-http = {
      port     = 80
      protocol = "HTTP"

      # Redirect HTTP to HTTPS
      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    # Blue/green rules live outside the module (aws_lb_listener_rule below)
    # because ECS rewrites their weights during every deployment.
    alb-https = {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = local.certificate_arn
      # TLS 1.3 + TLS 1.2 with forward-secret ciphers only. Without it the ALB
      # falls back to ELBSecurityPolicy-2016-08, which still allows TLS 1.0/1.1.
      ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"

      fixed_response = {
        content_type = "text/plain"
        message_body = "404: Page not found"
        status_code  = "404"
      }
    }
  }

  # Two identical target groups for the same nginx service: one serves
  # production, the other receives the new revision during a deployment.
  # ECS swaps their roles after each successful deployment.
  target_groups = {
    for key in ["blue-tg", "green-tg"] : key => {
      backend_protocol                  = "HTTP"
      backend_port                      = local.app_container_port
      target_type                       = "ip"
      deregistration_delay              = 5
      load_balancing_cross_zone_enabled = true

      health_check = {
        enabled             = true
        healthy_threshold   = 3
        interval            = 15
        matcher             = "200"
        path                = "/"
        port                = "traffic-port"
        protocol            = "HTTP"
        timeout             = 5
        unhealthy_threshold = 2
      }

      # There's nothing to attach here in this definition. Instead,
      # ECS will attach the IPs of the tasks to this target group
      create_attachment = false
    }
  }
  tags = local.tags
}

# Production traffic. Starts as blue 100 / green 0; during a deployment ECS
# shifts it to the new target group, so Terraform must not reset the weights.
resource "aws_lb_listener_rule" "production" {
  count        = var.enable_alb ? 1 : 0
  listener_arn = module.alb[0].listeners["alb-https"].arn
  priority     = 10

  action {
    type = "forward"
    forward {
      target_group {
        arn    = module.alb[0].target_groups["blue-tg"].arn
        weight = 100
      }
      target_group {
        arn    = module.alb[0].target_groups["green-tg"].arn
        weight = 0
      }
    }
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }

  lifecycle {
    ignore_changes = [action]
  }

  tags = local.tags
}

# Test traffic: requests with "X-Blue-Green: test" reach the new revision
# before any production traffic is shifted to it.
resource "aws_lb_listener_rule" "test" {
  count        = var.enable_alb ? 1 : 0
  listener_arn = module.alb[0].listeners["alb-https"].arn
  priority     = 1

  action {
    type = "forward"
    forward {
      target_group {
        arn    = module.alb[0].target_groups["green-tg"].arn
        weight = 100
      }
    }
  }

  condition {
    http_header {
      http_header_name = "X-Blue-Green"
      values           = ["test"]
    }
  }

  lifecycle {
    ignore_changes = [action]
  }

  tags = local.tags
}

resource "aws_route53_record" "alb_alias" {
  count   = var.enable_alb ? 1 : 0
  zone_id = var.hosted_zone_id
  name    = "${local.name}.${var.domain_name}" # poc-fargate.ailves2009.com
  type    = "A"
  alias {
    name                   = module.alb[0].dns_name
    zone_id                = module.alb[0].zone_id
    evaluate_target_health = false
  }
}

################################################################################
# IAM Roles and Policies
################################################################################
data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# Execution role: used by the ECS agent (not by app code) to pull images
# and ship container stdout to CloudWatch. Replaces the module default,
# which grants these actions on "*".
resource "aws_iam_policy" "task_exec" {
  name        = "ecspoc-task-exec"
  description = "ECS task execution role: pull images from this account's ECR, write to this project's log groups"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/ecs/poc-ecs-service*:*"
      },
      {
        # GetAuthorizationToken has no resource-level permissions
        Sid      = "EcrAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid      = "EcrPull"
        Effect   = "Allow"
        Action   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"]
        Resource = "arn:aws:ecr:${local.region}:${local.account_id}:repository/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_exec" {
  for_each   = toset(var.service_names)
  role       = try(module.ecs.services[each.key].task_exec_iam_role_name, module.ecs.task_exec_iam_role_name)
  policy_arn = aws_iam_policy.task_exec.arn
}

# Task role, poc-ecs-service only: the FireLens sidecar ships app logs
# to exactly one delivery stream.
resource "aws_iam_policy" "task_firehose" {
  name        = "ecspoc-task-firehose"
  description = "FireLens (fluent-bit) writes to the ${aws_kinesis_firehose_delivery_stream.firehose_stream.name} delivery stream"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["firehose:PutRecordBatch"]
      Resource = aws_kinesis_firehose_delivery_stream.firehose_stream.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "attach_tasks_firehose" {
  role       = try(module.ecs.services["poc-ecs-service"].tasks_iam_role_name, module.ecs.tasks_iam_role_name)
  policy_arn = aws_iam_policy.task_firehose.arn
}

# Task role, all services: the SSM agent inside the task records ECS Exec
# sessions in the exec log group (the module adds the ssmmessages actions).
resource "aws_iam_policy" "task_exec_audit" {
  name        = "ecspoc-task-exec-audit"
  description = "ECS Exec session logging to ${aws_cloudwatch_log_group.ecs_exec.name}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # DescribeLogGroups has no resource-level permissions
        Sid      = "DescribeLogGroups"
        Effect   = "Allow"
        Action   = ["logs:DescribeLogGroups"]
        Resource = "*"
      },
      {
        Sid      = "WriteExecLog"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:DescribeLogStreams", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.ecs_exec.arn}:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_tasks_exec_audit" {
  for_each   = toset(var.service_names)
  role       = try(module.ecs.services[each.key].tasks_iam_role_name, module.ecs.tasks_iam_role_name)
  policy_arn = aws_iam_policy.task_exec_audit.arn
}
