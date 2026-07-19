###############################################################################
# Primary outputs (id + arn)
###############################################################################

output "id" {
 description = "ID of the REST API."
 value = aws_api_gateway_rest_api.this.id
}

output "arn" {
 description = <<EOT
ARN of the REST API (cross-resource reference type:
arn:aws:apigateway:<region>::/restapis/<rest_api_id>). Consumed by IAM
policies scoping apigateway:* actions and by tf-mod-aws-wafv2 style
association patterns that key off REST API ARNs.
EOT
 value = aws_api_gateway_rest_api.this.arn
}

output "name" {
 description = "Name of the REST API."
 value = aws_api_gateway_rest_api.this.name
}

output "root_resource_id" {
 description = "Resource ID of the REST API's root (\"/\"). Wire as parent_id for a top-level aws_api_gateway_resource added outside this module, or leave resources[*].parent_key null to use it automatically."
 value = aws_api_gateway_rest_api.this.root_resource_id
}

output "execution_arn" {
 description = <<EOT
Execution ARN part (arn:aws:execute-api:<region>:<account>:<rest_api_id>),
used as the source_arn base in aws_lambda_permission when allowing this API
to invoke a backend Lambda -- concatenate with "/<stage>/<method><path>" (or
"/*/*/*" for a broad grant scoped to this API). Consumed by
tf-mod-aws-lambda callers wiring AWS_PROXY integrations.
EOT
 value = aws_api_gateway_rest_api.this.execution_arn
}

###############################################################################
# Resource tree
###############################################################################

output "resource_ids" {
 description = "Map of resources key => API Gateway resource ID."
 value = { for k, r in aws_api_gateway_resource.this: k => r.id }
}

output "resource_paths" {
 description = "Map of resources key => full resource path (including all parent paths)."
 value = { for k, r in aws_api_gateway_resource.this: k => r.path }
}

###############################################################################
# Methods / integrations / models / authorizers / validators
###############################################################################

output "method_ids" {
 description = "Map of methods key => \"<resource_id>/<http_method>\" (aws_api_gateway_method has no independent id)."
 value = { for k, m in aws_api_gateway_method.this: k => "${m.resource_id}/${m.http_method}" }
}

output "authorizer_ids" {
 description = "Map of authorizers key => authorizer ID."
 value = { for k, a in aws_api_gateway_authorizer.this: k => a.id }
}

output "model_ids" {
 description = "Map of models key => model ID."
 value = { for k, m in aws_api_gateway_model.this: k => m.id }
}

output "request_validator_ids" {
 description = "Map of request_validators key => validator ID."
 value = { for k, v in aws_api_gateway_request_validator.this: k => v.id }
}

###############################################################################
# Deployment / stages
###############################################################################

output "deployment_id" {
 description = "ID of the (single) deployment created by this module."
 value = aws_api_gateway_deployment.this.id
}

output "stage_ids" {
 description = "Map of stages key => stage ID."
 value = { for k, s in aws_api_gateway_stage.this: k => s.id }
}

output "stage_arns" {
 description = "Map of stages key => stage ARN, for CloudWatch/WAFv2 association."
 value = { for k, s in aws_api_gateway_stage.this: k => s.arn }
}

output "stage_invoke_urls" {
 description = "Map of stages key => invoke URL (the default execute-api endpoint for that stage)."
 value = { for k, s in aws_api_gateway_stage.this: k => s.invoke_url }
}

output "stage_execution_arns" {
 description = "Map of stages key => stage-scoped execution ARN, for a per-stage aws_lambda_permission source_arn."
 value = { for k, s in aws_api_gateway_stage.this: k => s.execution_arn }
}

output "stage_web_acl_arns" {
 description = "Map of stages key => associated WAFv2 web ACL ARN (null until a web ACL is associated, e.g. via tf-mod-aws-wafv2)."
 value = { for k, s in aws_api_gateway_stage.this: k => try(s.web_acl_arn, null) }
}

###############################################################################
# Custom domain names / base path mappings
###############################################################################

output "domain_name_ids" {
 description = "Map of domain_names key => internal API Gateway domain name identifier."
 value = { for k, d in aws_api_gateway_domain_name.this: k => d.id }
}

output "domain_name_arns" {
 description = "Map of domain_names key => domain name ARN."
 value = { for k, d in aws_api_gateway_domain_name.this: k => d.arn }
}

output "domain_name_cloudfront_domain_names" {
 description = "Map of domain_names key => CloudFront distribution hostname (EDGE domains only) -- alias target for a Route 53 record."
 value = { for k, d in aws_api_gateway_domain_name.this: k => try(d.cloudfront_domain_name, null) }
}

output "domain_name_regional_domain_names" {
 description = "Map of domain_names key => regional endpoint hostname (REGIONAL/PRIVATE domains) -- alias target for a Route 53 record."
 value = { for k, d in aws_api_gateway_domain_name.this: k => try(d.regional_domain_name, null) }
}

output "domain_name_regional_zone_ids" {
 description = "Map of domain_names key => hosted zone ID for a Route 53 alias record against the regional endpoint."
 value = { for k, d in aws_api_gateway_domain_name.this: k => try(d.regional_zone_id, null) }
}

output "base_path_mapping_keys" {
 description = "List of base_path_mappings keys created (this resource exports no attributes of its own)."
 value = keys(aws_api_gateway_base_path_mapping.this)
}

###############################################################################
# Usage plans / API keys
###############################################################################

output "usage_plan_ids" {
 description = "Map of usage_plans key => usage plan ID."
 value = { for k, u in aws_api_gateway_usage_plan.this: k => u.id }
}

output "usage_plan_arns" {
 description = "Map of usage_plans key => usage plan ARN."
 value = { for k, u in aws_api_gateway_usage_plan.this: k => u.arn }
}

output "api_key_ids" {
 description = "Map of api_keys key => API key ID."
 value = { for k, a in aws_api_gateway_api_key.this: k => a.id }
}

output "api_key_arns" {
 description = "Map of api_keys key => API key ARN."
 value = { for k, a in aws_api_gateway_api_key.this: k => a.arn }
}

output "api_key_values" {
 description = "Map of api_keys key => the API key value. SENSITIVE -- never appears in plan/apply output or logs."
 value = { for k, a in aws_api_gateway_api_key.this: k => a.value }
 sensitive = true
}

###############################################################################
# VPC Links
###############################################################################

output "vpc_link_ids" {
 description = "Map of vpc_links key => VPC Link ID. Wire into integrations[*].vpc_link_key (resolved automatically inside this module) or an external aws_api_gateway_integration."
 value = { for k, v in aws_api_gateway_vpc_link.this: k => v.id }
}

###############################################################################
# Client certificates
###############################################################################

output "client_certificate_ids" {
 description = "Map of client_certificates key => client certificate ID."
 value = { for k, c in aws_api_gateway_client_certificate.this: k => c.id }
}

output "client_certificate_arns" {
 description = "Map of client_certificates key => client certificate ARN."
 value = { for k, c in aws_api_gateway_client_certificate.this: k => c.arn }
}

###############################################################################
# Tags
###############################################################################

output "tags_all" {
 description = "All tags on the REST API, including those inherited from provider default_tags (resource tags win on key conflict)."
 value = aws_api_gateway_rest_api.this.tags_all
}
