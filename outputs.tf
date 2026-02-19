# poc-fargate/outputs.tf

output "vpc_id" {
  description = "VPC id used for ALB/target group"
  value       = var.vpc_id
}

output "subnets" {
  description = "Subnets used by the ECS service / ALB"
  value       = var.private_subnets
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = var.enable_alb ? module.alb[0].dns_name : ""
}

output "alb_zone_id" {
  description = "ALB Zone ID"
  value       = var.enable_alb ? module.alb[0].zone_id : ""
}

output "sg_ecs_id" {
  description = "ECS tasks security group id"
  value       = try(aws_security_group.sg_ecs.id, "")
}

output "sg_alb_id" {
  description = "ALB security group id"
  value       = var.enable_alb ? module.alb[0].security_group_id : ""
}

output "module_alb_security_group_id" {
  value = var.enable_alb ? module.alb[0].security_group_id : ""
}
output "module_alb_target_groups_poc_ecs_arn" {
  value = var.enable_alb ? module.alb[0].target_groups["poc-ecs-tg"].arn : ""
}
output "module_alb_target_groups_poc_ecs_name" {
  value = var.enable_alb ? module.alb[0].target_groups["poc-ecs-tg"].name : ""
}

output "infrastructure_iam_role_name" {
  value = module.ecs.infrastructure_iam_role_name
}
/*
output "node_iam_role_name" {
  value = module.ecs.node_iam_role_name
}
*/

output "cloudwatch_log_group_name" {
  value = module.ecs.cloudwatch_log_group_name
}
output "cluster_capacity_providers" {
  value = module.ecs.cluster_capacity_providers
}
/*
output "services" {
  value = module.ecs.services
}
*/
output "acm_certificate_arn" {
  description = "ARN of the ACM certificate for HTTPS"
  value       = local.certificate_arn
}
