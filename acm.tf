# poc-fargate/acm.tf

# Certificate for exactly one hostname (poc-fargate.<domain>), not a wildcard
# over the whole parent domain: a leaked key would only expose this service.
resource "aws_acm_certificate" "this" {
  count             = var.create_acm_certificate ? 1 : 0
  domain_name       = local.fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "validation" {
  provider = aws.dns
  for_each = var.create_acm_certificate ? {
    for dvo in aws_acm_certificate.this[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  } : {}
  zone_id         = var.hosted_zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  count                   = var.create_acm_certificate ? 1 : 0
  certificate_arn         = aws_acm_certificate.this[0].arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]
}

locals {
  fqdn            = "${local.name}.${var.domain_name}" # poc-fargate.ailves2009.com
  certificate_arn = var.create_acm_certificate ? aws_acm_certificate_validation.this[0].certificate_arn : var.acm_certificate_arn
}
