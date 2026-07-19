###############################################################################
# Local derivations
###############################################################################

locals {
 # Conditional singletons rendered via for_each over a 0/1-entry map so the
 # module never uses `count` (standard -- for_each only, even for a
 # single optional child resource).
 rest_api_policy = var.policy != null ? { this = var.policy }: {}
 account_settings = var.manage_account_settings ? { this = true }: {}

 # Automatic redeployment trigger: any change to the shape of the API
 # (resources/methods/integrations/etc.) forces a new deployment. Callers can
 # fold in additional values via deployment_trigger_resources.
 deployment_hash = sha1(jsonencode({
 resources = var.resources
 methods = var.methods
 method_responses = var.method_responses
 integrations = var.integrations
 integration_responses = var.integration_responses
 authorizers = var.authorizers
 models = var.models
 request_validators = var.request_validators
 gateway_responses = var.gateway_responses
 extra = var.deployment_trigger_resources
 }))
}

###############################################################################
# REST API (keystone)
#
# This module manages the API via the native resource/method/integration
# graph -- it deliberately does NOT expose the `body` (OpenAPI import)
# argument. See variables.tf / SCOPE.md for the rationale (mixing the two
# modes causes API Gateway to silently drop Terraform-managed child
# resources on the next body-driven update).
###############################################################################

resource "aws_api_gateway_rest_api" "this" {
 name = var.name
 description = var.description

 api_key_source = var.api_key_source
 binary_media_types = var.binary_media_types
 minimum_compression_size = var.minimum_compression_size
 disable_execute_api_endpoint = var.disable_execute_api_endpoint
 fail_on_warnings = var.fail_on_warnings

 endpoint_configuration {
 types = var.endpoint_configuration.types
 vpc_endpoint_ids = length(var.endpoint_configuration.vpc_endpoint_ids) > 0 ? var.endpoint_configuration.vpc_endpoint_ids: null
 ip_address_type = try(var.endpoint_configuration.ip_address_type, null)
 }

 tags = var.tags
}

###############################################################################
# REST API resource policy (separate resource -- avoids drift against the
# rest_api's own deprecated inline `policy` argument, per provider guidance)
###############################################################################

resource "aws_api_gateway_rest_api_policy" "this" {
 for_each = local.rest_api_policy

 rest_api_id = aws_api_gateway_rest_api.this.id
 policy = each.value
}

###############################################################################
# Resources -- the URL path tree (for_each, self-referential parent_id)
###############################################################################

resource "aws_api_gateway_resource" "this" {
 for_each = var.resources

 rest_api_id = aws_api_gateway_rest_api.this.id
 parent_id = (each.value.parent_key != null
 ? aws_api_gateway_resource.this[each.value.parent_key].id
: aws_api_gateway_rest_api.this.root_resource_id)
 path_part = each.value.path_part
}

###############################################################################
# Models / request validators / authorizers
###############################################################################

resource "aws_api_gateway_model" "this" {
 for_each = var.models

 rest_api_id = aws_api_gateway_rest_api.this.id
 name = each.value.name
 content_type = each.value.content_type
 description = try(each.value.description, null)
 schema = each.value.schema
}

resource "aws_api_gateway_request_validator" "this" {
 for_each = var.request_validators

 rest_api_id = aws_api_gateway_rest_api.this.id
 name = each.value.name
 validate_request_body = each.value.validate_request_body
 validate_request_parameters = each.value.validate_request_parameters
}

resource "aws_api_gateway_authorizer" "this" {
 for_each = var.authorizers

 rest_api_id = aws_api_gateway_rest_api.this.id
 name = each.value.name
 type = each.value.type
 authorizer_uri = try(each.value.authorizer_uri, null)
 authorizer_credentials = try(each.value.authorizer_credentials, null)
 identity_source = each.value.identity_source
 authorizer_result_ttl_in_seconds = each.value.authorizer_result_ttl_in_seconds
 identity_validation_expression = try(each.value.identity_validation_expression, null)
 provider_arns = length(each.value.provider_arns) > 0 ? each.value.provider_arns: null
}

###############################################################################
# Methods
#
# resource_id falls back to the REST API's root_resource_id when resource_key
# is null (a method attached directly at "/").
###############################################################################

resource "aws_api_gateway_method" "this" {
 for_each = var.methods

 rest_api_id = aws_api_gateway_rest_api.this.id
 resource_id = (each.value.resource_key != null
 ? aws_api_gateway_resource.this[each.value.resource_key].id
: aws_api_gateway_rest_api.this.root_resource_id)
 http_method = each.value.http_method

 authorization = each.value.authorization
 authorizer_id = each.value.authorizer_key != null ? aws_api_gateway_authorizer.this[each.value.authorizer_key].id: null
 authorization_scopes = length(each.value.authorization_scopes) > 0 ? each.value.authorization_scopes: null
 api_key_required = each.value.api_key_required
 operation_name = try(each.value.operation_name, null)
 request_models = length(each.value.request_models) > 0 ? each.value.request_models: null
 request_validator_id = each.value.request_validator_key != null ? aws_api_gateway_request_validator.this[each.value.request_validator_key].id: null
 request_parameters = length(each.value.request_parameters) > 0 ? each.value.request_parameters: null
}

resource "aws_api_gateway_method_response" "this" {
 for_each = var.method_responses

 rest_api_id = aws_api_gateway_rest_api.this.id
 resource_id = aws_api_gateway_method.this[each.value.method_key].resource_id
 http_method = aws_api_gateway_method.this[each.value.method_key].http_method
 status_code = each.value.status_code

 response_models = length(each.value.response_models) > 0 ? each.value.response_models: null
 response_parameters = length(each.value.response_parameters) > 0 ? each.value.response_parameters: null
}

###############################################################################
# Integrations
###############################################################################

resource "aws_api_gateway_integration" "this" {
 for_each = var.integrations

 rest_api_id = aws_api_gateway_rest_api.this.id
 resource_id = aws_api_gateway_method.this[each.value.method_key].resource_id
 http_method = aws_api_gateway_method.this[each.value.method_key].http_method

 type = each.value.type
 integration_http_method = try(each.value.integration_http_method, null)
 uri = try(each.value.uri, null)
 integration_target = try(each.value.integration_target, null)
 credentials = try(each.value.credentials, null)
 connection_type = each.value.connection_type
 connection_id = each.value.connection_type == "VPC_LINK" ? aws_api_gateway_vpc_link.this[each.value.vpc_link_key].id: null
 request_templates = length(each.value.request_templates) > 0 ? each.value.request_templates: null
 request_parameters = length(each.value.request_parameters) > 0 ? each.value.request_parameters: null
 passthrough_behavior = try(each.value.passthrough_behavior, null)
 content_handling = try(each.value.content_handling, null)
 timeout_milliseconds = each.value.timeout_milliseconds
 cache_key_parameters = length(each.value.cache_key_parameters) > 0 ? each.value.cache_key_parameters: null
 cache_namespace = try(each.value.cache_namespace, null)
 response_transfer_mode = each.value.response_transfer_mode

 dynamic "tls_config" {
 for_each = each.value.tls_config != null ? [each.value.tls_config]: []
 content {
 insecure_skip_verification = tls_config.value.insecure_skip_verification
 }
 }
}

resource "aws_api_gateway_integration_response" "this" {
 for_each = var.integration_responses

 rest_api_id = aws_api_gateway_rest_api.this.id
 resource_id = aws_api_gateway_method.this[each.value.method_key].resource_id
 http_method = aws_api_gateway_method.this[each.value.method_key].http_method
 status_code = each.value.status_code

 selection_pattern = try(each.value.selection_pattern, null)
 response_templates = length(each.value.response_templates) > 0 ? each.value.response_templates: null
 response_parameters = length(each.value.response_parameters) > 0 ? each.value.response_parameters: null
 content_handling = try(each.value.content_handling, null)

 depends_on = [aws_api_gateway_integration.this, aws_api_gateway_method_response.this]
}

###############################################################################
# Gateway responses (API-Gateway-generated error customization)
###############################################################################

resource "aws_api_gateway_gateway_response" "this" {
 for_each = var.gateway_responses

 rest_api_id = aws_api_gateway_rest_api.this.id
 response_type = each.value.response_type
 status_code = try(each.value.status_code, null)

 response_templates = length(each.value.response_templates) > 0 ? each.value.response_templates: null
 response_parameters = length(each.value.response_parameters) > 0 ? each.value.response_parameters: null
}

###############################################################################
# Deployment (single resource; hash-triggered redeployment)
#
# create_before_destroy is mandatory here -- without it API Gateway returns
# "Active stages pointing to this deployment must be moved or deleted" on
# recreation (provider docs). depends_on is explicit (not just the triggers
# hash) so the deployment is always ordered after every resource/method/
# integration it snapshots.
###############################################################################

resource "aws_api_gateway_deployment" "this" {
 rest_api_id = aws_api_gateway_rest_api.this.id
 description = var.deployment_description
 variables = var.deployment_variables

 triggers = {
 redeployment = local.deployment_hash
 }

 lifecycle {
 create_before_destroy = true
 }

 depends_on = [
 aws_api_gateway_resource.this,
 aws_api_gateway_method.this,
 aws_api_gateway_method_response.this,
 aws_api_gateway_integration.this,
 aws_api_gateway_integration_response.this,
 aws_api_gateway_authorizer.this,
 aws_api_gateway_model.this,
 aws_api_gateway_gateway_response.this,
 ]
}

###############################################################################
# Stages
#
# SECURE DEFAULT: xray_tracing_enabled true. Managed via the modern separated
# aws_api_gateway_stage resource (not the deployment's legacy stage_name
# argument), so method_settings below is safe to manage independently.
###############################################################################

resource "aws_api_gateway_stage" "this" {
 for_each = var.stages

 rest_api_id = aws_api_gateway_rest_api.this.id
 deployment_id = aws_api_gateway_deployment.this.id
 stage_name = each.value.stage_name

 xray_tracing_enabled = each.value.xray_tracing_enabled
 cache_cluster_enabled = each.value.cache_cluster_enabled
 cache_cluster_size = try(each.value.cache_cluster_size, null)
 client_certificate_id = each.value.client_certificate_key != null ? aws_api_gateway_client_certificate.this[each.value.client_certificate_key].id: null
 documentation_version = try(each.value.documentation_version, null)
 variables = each.value.variables

 dynamic "access_log_settings" {
 for_each = each.value.access_log_destination_arn != null ? [each.value]: []
 content {
 destination_arn = access_log_settings.value.access_log_destination_arn
 format = access_log_settings.value.access_log_format
 }
 }

 dynamic "canary_settings" {
 for_each = each.value.canary_settings != null ? [each.value.canary_settings]: []
 content {
 deployment_id = aws_api_gateway_deployment.this.id
 percent_traffic = try(canary_settings.value.percent_traffic, null)
 stage_variable_overrides = canary_settings.value.stage_variable_overrides
 use_stage_cache = canary_settings.value.use_stage_cache
 }
 }

 tags = merge(var.tags, each.value.tags)
}

resource "aws_api_gateway_method_settings" "this" {
 for_each = var.method_settings

 rest_api_id = aws_api_gateway_rest_api.this.id
 stage_name = aws_api_gateway_stage.this[each.value.stage_key].stage_name
 method_path = each.value.method_path

 settings {
 metrics_enabled = each.value.settings.metrics_enabled
 logging_level = each.value.settings.logging_level
 data_trace_enabled = each.value.settings.data_trace_enabled
 throttling_burst_limit = try(each.value.settings.throttling_burst_limit, null)
 throttling_rate_limit = try(each.value.settings.throttling_rate_limit, null)
 caching_enabled = each.value.settings.caching_enabled
 cache_ttl_in_seconds = try(each.value.settings.cache_ttl_in_seconds, null)
 cache_data_encrypted = each.value.settings.cache_data_encrypted
 require_authorization_for_cache_control = each.value.settings.require_authorization_for_cache_control
 unauthorized_cache_control_header_strategy = try(each.value.settings.unauthorized_cache_control_header_strategy, null)
 }
}

###############################################################################
# Client certificates (presented to backend HTTP(S) integrations)
###############################################################################

resource "aws_api_gateway_client_certificate" "this" {
 for_each = var.client_certificates

 description = try(each.value.description, null)
 tags = var.tags
}

###############################################################################
# Custom domain names, private-domain access associations, base path mappings
###############################################################################

resource "aws_api_gateway_domain_name" "this" {
 for_each = var.domain_names

 domain_name = each.value.domain_name

 certificate_arn = try(each.value.certificate_arn, null)
 regional_certificate_arn = try(each.value.regional_certificate_arn, null)
 security_policy = try(each.value.security_policy, null)
 endpoint_access_mode = try(each.value.endpoint_access_mode, null)
 policy = try(each.value.policy, null)
 ownership_verification_certificate_arn = try(each.value.ownership_verification_certificate_arn, null)

 endpoint_configuration {
 types = each.value.endpoint_configuration.types
 ip_address_type = try(each.value.endpoint_configuration.ip_address_type, null)
 }

 dynamic "mutual_tls_authentication" {
 for_each = each.value.mutual_tls_authentication != null ? [each.value.mutual_tls_authentication]: []
 content {
 truststore_uri = mutual_tls_authentication.value.truststore_uri
 truststore_version = try(mutual_tls_authentication.value.truststore_version, null)
 }
 }

 tags = merge(var.tags, each.value.tags)

 dynamic "timeouts" {
 for_each = (var.timeouts.create != null || var.timeouts.update != null) ? [var.timeouts]: []
 content {
 create = try(timeouts.value.create, null)
 update = try(timeouts.value.update, null)
 }
 }
}

resource "aws_api_gateway_domain_name_access_association" "this" {
 for_each = var.domain_name_access_associations

 domain_name_arn = aws_api_gateway_domain_name.this[each.value.domain_name_key].arn
 access_association_source = each.value.access_association_source
 access_association_source_type = each.value.access_association_source_type

 tags = var.tags
}

resource "aws_api_gateway_base_path_mapping" "this" {
 for_each = var.base_path_mappings

 api_id = aws_api_gateway_rest_api.this.id
 domain_name = aws_api_gateway_domain_name.this[each.value.domain_name_key].domain_name
 stage_name = each.value.stage_key != null ? aws_api_gateway_stage.this[each.value.stage_key].stage_name: null
 base_path = try(each.value.base_path, null)
}

###############################################################################
# Usage plans, API keys, and usage-plan-key associations
###############################################################################

resource "aws_api_gateway_usage_plan" "this" {
 for_each = var.usage_plans

 name = each.value.name
 description = try(each.value.description, null)
 product_code = try(each.value.product_code, null)

 dynamic "api_stages" {
 for_each = each.value.api_stages
 content {
 api_id = aws_api_gateway_rest_api.this.id
 stage = aws_api_gateway_stage.this[api_stages.value.stage_key].stage_name

 dynamic "throttle" {
 for_each = api_stages.value.throttle
 content {
 path = throttle.value.path
 burst_limit = try(throttle.value.burst_limit, null)
 rate_limit = try(throttle.value.rate_limit, null)
 }
 }
 }
 }

 dynamic "quota_settings" {
 for_each = each.value.quota_settings != null ? [each.value.quota_settings]: []
 content {
 limit = quota_settings.value.limit
 offset = try(quota_settings.value.offset, null)
 period = quota_settings.value.period
 }
 }

 dynamic "throttle_settings" {
 for_each = each.value.throttle_settings != null ? [each.value.throttle_settings]: []
 content {
 burst_limit = try(throttle_settings.value.burst_limit, null)
 rate_limit = try(throttle_settings.value.rate_limit, null)
 }
 }

 tags = var.tags
}

resource "aws_api_gateway_api_key" "this" {
 for_each = var.api_keys

 name = each.value.name
 description = try(each.value.description, null)
 enabled = each.value.enabled
 value = try(each.value.value, null)
 customer_id = try(each.value.customer_id, null)

 tags = var.tags
}

resource "aws_api_gateway_usage_plan_key" "this" {
 for_each = var.usage_plan_keys

 key_id = aws_api_gateway_api_key.this[each.value.api_key_key].id
 key_type = each.value.key_type
 usage_plan_id = aws_api_gateway_usage_plan.this[each.value.usage_plan_key].id
}

###############################################################################
# VPC Links (private integrations to an internal NLB)
###############################################################################

resource "aws_api_gateway_vpc_link" "this" {
 for_each = var.vpc_links

 name = each.value.name
 description = try(each.value.description, null)
 target_arns = each.value.target_arns

 tags = var.tags
}

###############################################################################
# Documentation
###############################################################################

resource "aws_api_gateway_documentation_part" "this" {
 for_each = var.documentation_parts

 rest_api_id = aws_api_gateway_rest_api.this.id
 properties = each.value.properties

 location {
 type = each.value.location.type
 method = try(each.value.location.method, null)
 name = try(each.value.location.name, null)
 path = try(each.value.location.path, null)
 status_code = try(each.value.location.status_code, null)
 }
}

resource "aws_api_gateway_documentation_version" "this" {
 for_each = var.documentation_versions

 rest_api_id = aws_api_gateway_rest_api.this.id
 version = each.value.version
 description = try(each.value.description, null)

 depends_on = [aws_api_gateway_documentation_part.this]
}

###############################################################################
# Account settings (region-wide singleton, opt-in)
###############################################################################

resource "aws_api_gateway_account" "this" {
 for_each = local.account_settings

 cloudwatch_role_arn = var.account_cloudwatch_role_arn
}
