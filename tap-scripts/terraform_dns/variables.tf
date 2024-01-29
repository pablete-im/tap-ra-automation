variable "aws_region" {
  description = "The aws region. https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-regions-availability-zones.html"
  type        = string
  default     = "eu-west-1"
}

variable "run_nlb_dns_name" {
  description = "Public DNS name of the AWS Network Load Balancer for the Run profile."
  type = string
}

variable "run_nlb_zone_id" {
  description = "The canonical hosted zone ID of the Run profile NLB (to be used in a Route 53 Alias record)."
  type        = string
}

variable "run_route53_hosted_zone_id" {
  description = "The ID of the hosted zone to contain this record for the Run profile."
  type        = string
}

variable "run_full_domain" {
  description = "The full domain for the Run profile, e.g. tap-run.example.com"
  type        = string
}

variable "iterate_alb_dns_name" {
  description = "Public DNS name of the AWS Application Load Balancer for the Iterate profile."
  type = string
}

variable "iterate_alb_zone_id" {
  description = "The canonical hosted zone ID of the Iterate profile ALB (to be used in a Route 53 Alias record)."
  type        = string
}

variable "iterate_route53_hosted_zone_id" {
  description = "The ID of the hosted zone to contain this record for the Iterate profile."
  type        = string
}

variable "iterate_full_domain" {
  description = "The full domain for the Iterate profile, e.g. tap-iterate.example.com"
  type        = string
}

variable "view_alb_dns_name" {
  description = "Public DNS name of the AWS Application Load Balancer for the View profile."
  type = string
}

variable "view_alb_zone_id" {
  description = "The canonical hosted zone ID of the View profile ALB (to be used in a Route 53 Alias record)."
  type        = string
}

variable "view_route53_hosted_zone_id" {
  description = "The ID of the hosted zone to contain this record for the View profile."
  type        = string
}

variable "view_full_domain" {
  description = "The full domain for the View profile, e.g. tap-view.example.com"
  type        = string
}

variable "view_apiportal_domain" {
  description = "The api portal domain for the View profile, e.g. api-portal.subdomain.example.com"
  type        = string
}

variable "view_appliveview_domain" {
  description = "The app live view domain for the View profile, e.g. app-live-view.subdomain.example.com"
  type        = string
}

variable "view_metadatastore_domain" {
  description = "The metadata store domain for the View profile, e.g. metadata-store.subdomain.example.com"
  type        = string
}

variable "view_tapgui_domain" {
  description = "The tap-gui domain for the View profile, e.g. tap-gui.subdomain.example.com"
  type        = string
}

variable "view_learningcenter_domain" {
  description = "The learning center domain for the View profile, e.g. learning.subdomain.example.com"
  type        = string
}