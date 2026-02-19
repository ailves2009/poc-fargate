# poc-fargate/acm.tf

resource "aws_acm_certificate" "wildcard" {
  count                     = var.create_acm_certificate ? 1 : 0
  domain_name               = "*.${var.domain_name}"
  subject_alternative_names = [var.domain_name]
  validation_method         = "DNS"
}

resource "aws_route53_record" "validation" {
  for_each = var.create_acm_certificate ? {
    for dvo in aws_acm_certificate.wildcard[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  } : {}
  zone_id         = data.aws_route53_zone.selected.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  count                   = var.create_acm_certificate ? 1 : 0
  certificate_arn         = aws_acm_certificate.wildcard[0].arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]
}

locals {
  certificate_arn = var.create_acm_certificate ? aws_acm_certificate_validation.this[0].certificate_arn : var.acm_certificate_arn
}

data "aws_route53_zone" "selected" {
  name = var.domain_name
}
