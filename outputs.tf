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

output "alb_full_dns_name" {
  description = "Route53 record FQDN for the service"
  value       = var.enable_alb ? aws_route53_record.alb_alias[0].fqdn : ""
}

output "sg_alb_id" {
  description = "ALB security group id"
  value       = var.enable_alb ? module.alb[0].security_group_id : ""
}

output "module_alb_security_group_id" {
  value = var.enable_alb ? module.alb[0].security_group_id : ""
}
output "target_group_arns" {
  description = "Blue/green target groups of the nginx service (ECS swaps their roles after each deployment)"
  value = var.enable_alb ? {
    blue  = module.alb[0].target_groups["blue-tg"].arn
    green = module.alb[0].target_groups["green-tg"].arn
  } : null
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

output "blue_green_test_command" {
  description = "Reach the new revision through the test listener rule during a blue/green deployment"
  value       = var.enable_alb ? "curl -H 'X-Blue-Green: test' https://${aws_route53_record.alb_alias[0].fqdn}/" : ""
}
