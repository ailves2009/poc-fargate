# poc-fargate/main.tf

# This file defines an example of using the terraform-aws-ecs module to create a Fargate service with an ALB, 
# including two services (poc-ecs-service and nginx-service) with different container definitions and LB TGs. 
# It also includes the necessary IAM policies for the tasks to pull from ECR and write to CloudWatch Logs, 
# as well as a Service Discovery namespace for the services to register with.

data "aws_availability_zones" "available" {
  # Exclude local zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  region = var.region
  name   = basename(path.cwd)

  vpc_cidr = var.vpc_cidr
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  poc_container_name = "poc-ecs-app"
  app_container_name = "nginx"
  poc_container_port = var.poc_container_port
  app_container_port = var.app_container_port

  tags = {
    Name       = local.name
    File       = "iaac/components/terraform/fargate/new.tf"
    Repository = "https://github.com/terraform-aws-modules/terraform-aws-ecs"
  }
}
/*
resource "aws_cloudwatch_log_group" "ecspoc_ecs_app" {
  name              = "/ecs/ecs-integrated/${local.poc_container_name}"
  retention_in_days = var.log_retention
  tags              = local.tags
}
*/
################################################################################
# Cluster
################################################################################

module "ecs" {
  source = "terraform-aws-modules/ecs/aws"

  cluster_name = "ecs-integrated"

  cluster_configuration = {
    execute_command_configuration = {
      logging = "OVERRIDE"
      log_configuration = {
        cloud_watch_log_group_name = "/aws/ecs/aws-ec2"
      }
    }
  }

  # Cluster capacity providers
  cluster_capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  default_capacity_provider_strategy = {
    FARGATE = {
      weight = 50
      base   = 20
    }
    FARGATE_SPOT = {
      weight = 50
    }
  }

  services = {
    poc-ecs-service = {
      enable_execute_command = true
      cpu                    = var.service_cpu
      memory                 = var.service_memory
      desired_count          = var.desired_count

      container_definitions = {
        fluent-bit = {
          cpu               = var.fluent_bit_cpu
          memory            = var.fluent_bit_memory
          essential         = true
          image             = var.fluent_bit_image
          memoryReservation = 50
          firelensConfiguration = {
            type = "fluentbit"
          }
          environment = [
            {
              name  = "FIREHOSE_STREAM"
              value = aws_kinesis_firehose_delivery_stream.firehose_stream.name
            },
            {
              name  = "LOG_GROUP"
              value = "/aws/ecs/poc-ecs-service/poc-ecs-app"
            },
            {
              name  = "AWS_REGION"
              value = local.region
            }
          ]
        }

        poc-ecs-app = {
          cpu               = var.poc_app_cpu
          memory            = var.poc_app_memory
          essential         = true
          image             = var.poc_app_image
          memoryReservation = 100
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

          enable_cloudwatch_logging = true
          logConfiguration = {
            logDriver = "awsfirelens"
            options = {
              Name                    = "firehose"
              region                  = local.region
              delivery_stream         = "${local.name}-firehose-stream"
              log-driver-buffer-limit = "2097152"
            }
          }
          /*
          logConfiguration = {
            logDriver = "awslogs"
            options = {
              "awslogs-group"         = "/ecs/${local.name}/${local.poc_container_name}"
              "awslogs-region"        = local.region
              "awslogs-stream-prefix" = "ecs"
            }
          }
          */
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

      load_balancer = var.enable_alb ? {
        service = {
          target_group_arn = module.alb[0].target_groups["green-tg"].arn
          container_name   = local.poc_container_name
          container_port   = local.poc_container_port
        }
      } : {}

      subnet_ids = var.private_subnets

      security_group_ingress_rules = var.enable_alb ? {
        alb_3000 = {
          description                  = "ASG ECS module alb_3000"
          from_port                    = local.poc_container_port
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
    poc-ecs-service-rc = {
      enable_execute_command = true
      cpu                    = var.service_cpu
      memory                 = var.service_memory
      desired_count          = var.desired_count

      container_definitions = {

        fluent-bit = {
          cpu       = var.fluent_bit_cpu
          memory    = var.fluent_bit_memory
          essential = true
          image     = var.fluent_bit_image
          /*
          firelensConfiguration = {
            type = "fluentbit"
          } */
          memoryReservation = 50
        }

        nginx = {
          cpu               = var.nginx_cpu
          memory            = var.nginx_memory
          essential         = true
          image             = var.nginx_image
          memoryReservation = 100
          portMappings = [
            {
              name          = local.app_container_name
              containerPort = local.app_container_port
              protocol      = "tcp"
            }
          ]
          healthCheck = {
            command     = ["CMD-SHELL", "curl -f http://localhost:${local.app_container_port}/ || exit 1"]
            interval    = 30
            timeout     = 5
            retries     = 3
            startPeriod = 60
          }
          # enable awslogs for CloudWatch
          enable_cloudwatch_logging = true
          logConfiguration = {
            logDriver = "awslogs"
            options = {
              "awslogs-group"         = "/aws/ecs/poc-ecs-service-rc"
              "awslogs-region"        = local.region
              "awslogs-stream-prefix" = "${local.app_container_name}"
            }
          }
          # use awsfirelens so fluent-bit can collect logs
          /*
          enable_cloudwatch_logging = false
          logConfiguration = {
            logDriver = "awsfirelens"
            options = {
              Name            = "firehose"
              region          = local.region
              delivery_stream = "firehose-stream"
              # optional buffer limit
              "log-driver-buffer-limit" = "2097152"
            }
          }
          */
          # Example image used requires access to write to root filesystem
          readonlyRootFilesystem = false

          dependsOn = [{
            containerName = "fluent-bit"
            condition     = "START"
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
        }
      } : {}

      subnet_ids = var.private_subnets

      security_group_ingress_rules = var.enable_alb ? {
        alb_3000 = {
          description = "ECS module - security_group_ingress_rules"
          from_port   = local.app_container_port
          to_port     = local.app_container_port
          ip_protocol = "tcp"
          # referenced_security_group_id = "sg-12345678"
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

  tags = {
    Environment = "poc"
    Project     = "poc-fargate"
  }
}

################################################################################
# Supporting Resources (ALB, IAM Roles/Policies, etc.)
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

    alb-https = {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = local.certificate_arn

      fixed_response = {
        content_type = "text/plain"
        message_body = "404: Page not found"
        status_code  = "404"
      }

      # for blue/green deployments
      rules = {
        production = {
          priority = 1
          actions = [
            {
              weighted_forward = {
                target_groups = [
                  {
                    target_group_key = "green-tg"
                    weight           = 100
                  },
                  {
                    target_group_key = "blue-tg"
                    weight           = 0
                  }
                ]
              }
            }
          ]
          conditions = [
            {
              path_pattern = {
                values = ["/*"]
              }
            }
          ]
        }
        test = {
          priority = 2
          actions = [
            {
              weighted_forward = {
                target_groups = [
                  {
                    target_group_key = "blue-tg"
                    weight           = 100
                  }
                ]
              }
            }
          ]
          conditions = [
            {
              path_pattern = {
                values = ["/*"]
              }
            }
          ]
        }
      }
    }
  }

  target_groups = {
    green-tg = {
      backend_protocol                  = "HTTP"
      backend_port                      = local.poc_container_port
      target_type                       = "ip"
      deregistration_delay              = 5
      load_balancing_cross_zone_enabled = true

      health_check = {
        enabled           = true
        healthy_threshold = 3
        interval          = 30
        matcher           = "200-399"
        path              = "/"
        # port                = "traffic-port"
        port                = tostring(local.poc_container_port)
        protocol            = "HTTP"
        timeout             = 10
        unhealthy_threshold = 2
      }

      # There's nothing to attach here in this definition. Instead,
      # ECS will attach the IPs of the tasks to this target group
      create_attachment = false
    }

    # for blue/green deployments
    blue-tg = {
      backend_protocol = "HTTP"
      # backend_port                      = local.container_port
      backend_port                      = local.app_container_port
      target_type                       = "ip"
      deregistration_delay              = 5
      load_balancing_cross_zone_enabled = true

      health_check = {
        enabled           = true
        healthy_threshold = 5
        interval          = 30
        matcher           = "200"
        path              = "/"
        port              = local.app_container_port
        # port                = tostring(local.container_port)
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

resource "aws_route53_record" "alb_alias" {
  count   = var.enable_alb ? 1 : 0
  zone_id = var.hosted_zone_id
  name    = "${local.name}.${var.domain_name}" # poc-fargate.bmta.echotwin.ai
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

resource "aws_iam_policy" "ecspoc_firehose_put" {
  name        = "ecspoc-firehose-put"
  description = "Allow PutRecord and PutRecordBatch to delivery stream my-stream"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["firehose:PutRecord", "firehose:PutRecordBatch"]
      # Resource = "arn:aws:firehose:*:${data.aws_caller_identity.current.account_id}:deliverystream/my-stream"
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "attach_tasks_firehose" {
  for_each   = toset(var.service_names)
  role       = try(module.ecs.services[each.key].tasks_iam_role_name, module.ecs.tasks_iam_role_name)
  policy_arn = aws_iam_policy.ecspoc_firehose_put.arn
}

resource "aws_iam_role_policy_attachment" "attach_exec_firehose" {
  for_each   = toset(var.service_names)
  role       = try(module.ecs.services[each.key].task_exec_iam_role_name, module.ecs.task_exec_iam_role_name)
  policy_arn = aws_iam_policy.ecspoc_firehose_put.arn
}

resource "aws_iam_role_policy_attachment" "attach_exec_awslogs" {
  for_each   = toset(var.service_names)
  role       = try(module.ecs.services[each.key].task_exec_iam_role_name, module.ecs.task_exec_iam_role_name)
  policy_arn = aws_iam_policy.awslogs_put.arn
}
# IAM Policy for ECS tasks to allow writing to Firehose delivery stream "my-stream"

resource "aws_iam_policy" "ecr_pull" {
  name        = "ecspoc-ecr-pull"
  description = "Allow ECS task execution role to pull images from ECR"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = "arn:aws:ecr:${local.region}:${data.aws_caller_identity.current.account_id}:repository/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_exec_ecr" {
  for_each   = toset(var.service_names)
  role       = try(module.ecs.services[each.key].task_exec_iam_role_name, module.ecs.task_exec_iam_role_name)
  policy_arn = aws_iam_policy.ecr_pull.arn
}

## IAM Policy for ECS task execution role to allow creating/putting CloudWatch Logs
resource "aws_iam_policy" "awslogs_put" {
  name        = "ecspoc-awslogs-put"
  description = "Allow ECS task execution roles to create/put CloudWatch Logs"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "firehose:PutRecordBatch"
        ]
        Resource = "arn:aws:logs:${local.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/ecs/*"
      }
    ]
  })
}

## IAM Policy for ECS task role to allow Firehose + CloudWatch Logs
resource "aws_iam_policy" "task_logs_firehose_put" {
  name        = "ecspoc-task-logs-firehose"
  description = "Allow ECS task role to put Firehose records and CloudWatch Logs"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "firehose:PutRecord",
          "firehose:PutRecordBatch"
        ]
        Resource = "arn:aws:firehose:${local.region}:${data.aws_caller_identity.current.account_id}:deliverystream/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${local.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/ecs/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_tasks_logs_firehose" {
  for_each   = toset(var.service_names)
  role       = try(module.ecs.services[each.key].tasks_iam_role_name, module.ecs.tasks_iam_role_name)
  policy_arn = aws_iam_policy.task_logs_firehose_put.arn
}

