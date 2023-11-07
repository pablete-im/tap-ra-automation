# Copyright 2022 VMware, Inc.
# SPDX-License-Identifier: BSD-2-Clause

# Route53 Alias record for the Run cluster NLB
resource "aws_route53_record" "tap_run_record" {
  zone_id = var.run_route53_hosted_zone_id
  name    = var.run_full_domain
  type    = "A"

  alias {
    name                   = var.run_nlb_dns_name
    zone_id                = var.run_nlb_zone_id
    evaluate_target_health = true
  }
}

# Route53 Alias record for the View cluster ALB
resource "aws_route53_record" "tap_view_record" {
  zone_id = var.view_route53_hosted_zone_id
  name    = var.view_full_domain
  type    = "A"

  alias {
    name                   = var.view_alb_dns_name
    zone_id                = var.view_alb_zone_id
    evaluate_target_health = true
  }
}

# Route53 Alias record for the View cluster ALB
resource "aws_route53_record" "tap_iterate_record" {
  zone_id = var.iterate_route53_hosted_zone_id
  name    = var.iterate_full_domain
  type    = "A"

  alias {
    name                   = var.iterate_alb_dns_name
    zone_id                = var.iterate_alb_zone_id
    evaluate_target_health = true
  }
}