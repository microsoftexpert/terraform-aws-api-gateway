terraform {
 required_version = ">= 1.12.0"

 required_providers {
 aws = {
 source = "hashicorp/aws"
 version = ">= 6.0, < 7.0"
 }
 }
}

###############################################################################
# Region / provider wiring (read before use)
#
# This module does NOT declare a `region` variable (region model) and does
# NOT hard-code a provider. The REST API and every child resource (resources,
# methods, integrations, deployment, stages, domain names, usage plans,...)
# are all created with the single inherited `aws` provider, so the *caller*
# decides the Region by choosing which provider configuration to pass into the
# `aws` slot.
#
# Unlike tf-mod-aws-cloudfront / tf-mod-aws-wafv2 (CLOUDFRONT scope) / the
# CloudFront-facing tf-mod-aws-acm call, API Gateway V1 REST APIs are a
# REGIONAL or EDGE-optimized service managed from the Region the API lives in
# -- there is NO us-east-1 requirement for this module itself. The only
# us-east-1 coupling that can appear here is indirect: an EDGE-optimized
# custom domain name's ACM certificate (certificate_arn on
# aws_api_gateway_domain_name) MUST be requested in us-east-1 (API Gateway
# EDGE domains sit behind an AWS-managed CloudFront distribution), while a
# REGIONAL custom domain's certificate (regional_certificate_arn) must be in
# the SAME Region as the API. Wire the correct tf-mod-aws-acm call for the
# endpoint type you choose.
#
# module "rest_api" {
# source = "git::https://github.com/microsoftexpert/tf-mod-aws-api-gateway?ref=v1.0.0"
# # inherits the default `aws` provider (whatever Region it points at)
# name = "core-rest-api"
#...
# }
#
# Provider credentials, default_tags and assume_role all live in the caller's
# provider block -- never in this module.
###############################################################################
