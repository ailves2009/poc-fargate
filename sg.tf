# poc-fargate/sg.tf

resource "aws_security_group" "sg_ecs" {
  name        = "sg_ecs-${local.name}"
  description = "SG for ECS tasks"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = var.sg_ssh_port
    to_port     = var.sg_ssh_port
    protocol    = "tcp"
    cidr_blocks = var.ssh_cidr_blocks
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.ssh_cidr_blocks
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.ssh_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "sg_alb" {
  name        = "sg_alb-${local.name}"
  description = "SG for ALB"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = var.sg_ssh_port
    to_port     = var.sg_ssh_port
    protocol    = "tcp"
    cidr_blocks = var.ssh_cidr_blocks
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.ssh_cidr_blocks
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.ssh_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# VPC Endpoints to allow ECS tasks to pull images from ECR without using the Internet/NAT
resource "aws_security_group" "sg_vpc_endpoint" {
  name        = "sg_vpc-endpoint-${local.name}"
  description = "SG for interface VPC endpoints (ECR)"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_ecs.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
