###############################################################################
# Identity
###############################################################################

variable "name" {
 description = <<EOT
Name of the REST API (aws_api_gateway_rest_api.this). Not unique in the
account/Region -- API Gateway allows duplicate names -- so keep names
descriptive for humans and rely on the id/arn outputs for wiring.
EOT
 type = string

 validation {
 condition = length(var.name) > 0 && length(var.name) <= 1024
 error_message = "name must be between 1 and 1024 characters."
 }
}

variable "description" {
 description = "Description of the REST API."
 type = string
 default = null
}

###############################################################################
# REST API configuration
#
# This module manages the REST API via the native Terraform resource graph
# (aws_api_gateway_resource / method / integration, etc.) -- it deliberately
# does NOT expose the OpenAPI `body` import path (the rest_api `body` argument
# or the aws_api_gateway_rest_api_put resource). See SCOPE.md "Out-of-scope
# resources" and README Architecture Notes for the rationale: mixing an
# OpenAPI-body-driven API with Terraform-managed child resources is explicitly
# called out by the provider docs as unsafe (updates to one silently overwrite
# the other). Callers who want an OpenAPI/Swagger-driven REST API should
# compose aws_api_gateway_rest_api_put directly against this module's `id`
# output rather than requesting a dual-mode module.
###############################################################################

variable "endpoint_configuration" {
 description = <<EOT
API endpoint configuration.

 - types: list of endpoint types. SECURE DEFAULT / baseline:
 ["REGIONAL"] -- NOT AWS's own implicit default of
 ["EDGE"]. REGIONAL keeps the execute-api endpoint in
 the same Region as the API (no implicit CloudFront
 distribution) and is the recommended posture for
 internal/PII-adjacent APIs. Use ["EDGE"] deliberately
 for a globally distributed public API, or ["PRIVATE"]
 for a VPC-endpoint-only API (requires vpc_endpoint_ids).
 Only a single value is supported by the provider.
 - vpc_endpoint_ids: VPC endpoint IDs for a PRIVATE API. Wire from
 tf-mod-aws-vpc-endpoint (service com.amazonaws.<region>.execute-api).
 - ip_address_type: "ipv4" (default) or "dualstack". "PRIVATE" APIs only
 support "dualstack".
EOT
 type = object({
 types = optional(list(string), ["REGIONAL"])
 vpc_endpoint_ids = optional(list(string), [])
 ip_address_type = optional(string)
 })
 default = {}

 validation {
 condition = alltrue([for t in var.endpoint_configuration.types: contains(["EDGE", "REGIONAL", "PRIVATE"], t)])
 error_message = "endpoint_configuration.types values must be one of: EDGE, REGIONAL, PRIVATE."
 }
}

variable "policy" {
 description = <<EOT
JSON resource policy controlling access to the API Gateway execute-api
endpoint. Rendered as a SEPARATE aws_api_gateway_rest_api_policy.this (not the
rest_api's own inline `policy` argument, which the provider docs recommend
against for drift reasons). Required for PRIVATE APIs (must scope access to
specific VPC endpoints). Leave null to skip.
EOT
 type = string
 default = null
}

variable "api_key_source" {
 description = "Source of the API key for requests. One of: HEADER (default), AUTHORIZER."
 type = string
 default = "HEADER"

 validation {
 condition = contains(["HEADER", "AUTHORIZER"], var.api_key_source)
 error_message = "api_key_source must be one of: HEADER, AUTHORIZER."
 }
}

variable "binary_media_types" {
 description = "List of binary media types supported by the REST API (e.g. [\"application/octet-stream\"]). Empty (default) supports only UTF-8 text payloads."
 type = list(string)
 default = []
}

variable "minimum_compression_size" {
 description = "Minimum response size in bytes to compress, as a string between \"-1\" and \"10485760\". Null (default) disables compression."
 type = string
 default = null
}

variable "disable_execute_api_endpoint" {
 description = <<EOT
Whether the default https://{api_id}.execute-api.{region}.amazonaws.com
endpoint is disabled, forcing clients to use a custom domain name. Defaults to
false (AWS default). Set true only after a custom domain name (domain_names)
is fully wired -- disabling the default endpoint before a working custom
domain exists locks out all callers.
EOT
 type = bool
 default = false
}

variable "fail_on_warnings" {
 description = "Whether to return an error for warnings on REST API creation/update. Defaults to false (AWS default)."
 type = bool
 default = false
}

###############################################################################
# Resources (the URL path tree) -- for_each over map(object), self-referential
#
# Keyed by a stable caller string. parent_key references another key in this
# same map; leave parent_key null to attach directly under the API root
# (root_resource_id). Every other child collection (methods, models via
# request validation, documentation_parts) references resources by this key.
###############################################################################

variable "resources" {
 description = <<EOT
Map of API Gateway resources (URL path segments) keyed by a stable name, each
rendered as one aws_api_gateway_resource. Builds the resource tree.

 - parent_key: key of another entry in this map to nest under. Null
 (default) attaches directly under the REST API's root
 resource (root_resource_id).
 - path_part: last path segment for this resource (e.g. "users", "{id}",
 "{proxy+}" for a greedy proxy resource).
EOT
 type = map(object({
 parent_key = optional(string)
 path_part = string
 }))
 default = {}
}

###############################################################################
# Models / request validators / authorizers
###############################################################################

variable "models" {
 description = <<EOT
Map of API Gateway models keyed by a stable name, each rendered as one
aws_api_gateway_model. Referenced by methods[*].request_models /
method_responses[*].response_models (by the model's `name`, not this map key --
API Gateway request/response model maps are keyed by content type -> model
name).

 - name: model name (referenced by content-type maps elsewhere).
 - content_type: content type this schema applies to. Default "application/json".
 - schema: JSON Schema (draft-04) document as a string, e.g.
 jsonencode({ type = "object"... }).
 - description: optional human-readable description.
EOT
 type = map(object({
 name = string
 content_type = optional(string, "application/json")
 schema = string
 description = optional(string)
 }))
 default = {}
}

variable "request_validators" {
 description = <<EOT
Map of request validators keyed by a stable name, each rendered as one
aws_api_gateway_request_validator. Referenced by methods[*].request_validator_key.

 - name: validator name.
 - validate_request_body: validate the request body against the
 method's request_models. Default false.
 - validate_request_parameters: validate required request_parameters
 (path/query/header). Default false.
EOT
 type = map(object({
 name = string
 validate_request_body = optional(bool, false)
 validate_request_parameters = optional(bool, false)
 }))
 default = {}
}

variable "authorizers" {
 description = <<EOT
Map of API Gateway authorizers keyed by a stable name, each rendered as one
aws_api_gateway_authorizer. Referenced by methods[*].authorizer_key.

 - name: authorizer name.
 - type: "TOKEN" (single header, default),
 "REQUEST" (multiple params), or
 "COGNITO_USER_POOLS".
 - authorizer_uri: Lambda invoke ARN in the form
 arn:aws:apigateway:{region}:lambda:path/....
 Required for TOKEN/REQUEST. Wire from
 tf-mod-aws-lambda (invoke_arn output).
 - authorizer_credentials: IAM role ARN API Gateway assumes to
 invoke the authorizer Lambda. Wire from
 tf-mod-aws-iam-role.
 - identity_source: where the identity is read from.
 Default "method.request.header.Authorization".
 - authorizer_result_ttl_in_seconds: cache TTL for authorizer results (0-3600).
 Default 300.
 - identity_validation_expression: regex validated against the TOKEN value.
 - provider_arns: Cognito user pool ARNs. Required for
 COGNITO_USER_POOLS. Wire from
 tf-mod-aws-cognito.
EOT
 type = map(object({
 name = string
 type = optional(string, "TOKEN")
 authorizer_uri = optional(string)
 authorizer_credentials = optional(string)
 identity_source = optional(string, "method.request.header.Authorization")
 authorizer_result_ttl_in_seconds = optional(number, 300)
 identity_validation_expression = optional(string)
 provider_arns = optional(list(string), [])
 }))
 default = {}

 validation {
 condition = alltrue([for k, v in var.authorizers: contains(["TOKEN", "REQUEST", "COGNITO_USER_POOLS"], v.type)])
 error_message = "Each authorizers[*].type must be one of: TOKEN, REQUEST, COGNITO_USER_POOLS."
 }
}

###############################################################################
# Methods (child collection -- for_each over map(object))
#
# SECURE DEFAULT NOTE: authorization has NO default here -- it is a required
# field on every methods[*] entry. A method's authorization must never
# silently resolve to "NONE"; the caller states it explicitly every time.
###############################################################################

variable "methods" {
 description = <<EOT
Map of HTTP methods keyed by a stable name, each rendered as one
aws_api_gateway_method. Referenced by integrations / method_responses /
integration_responses / method_settings (method_key) and surfaced for
authorizer/API-key wiring.

 - resource_key: key of the resource (in resources) this method
 attaches to. Null attaches to the API root.
 - http_method: "GET", "POST", "PUT", "DELETE", "HEAD", "OPTIONS",
 or "ANY".
 - authorization: REQUIRED, no default -- one of "NONE", "CUSTOM",
 "AWS_IAM", "COGNITO_USER_POOLS". Every method must
 state its authorization explicitly (baseline:
 never silently NONE).
 - authorizer_key: key of the authorizer (in authorizers) to attach.
 Required when authorization is CUSTOM or
 COGNITO_USER_POOLS.
 - authorization_scopes: Cognito scopes required (COGNITO_USER_POOLS only).
 - api_key_required: whether an API key is required. Default false.
 - operation_name: friendly SDK-generation name. Optional.
 - request_models: map of content-type -> model name (built-ins
 "Error"/"Empty", or a models[*].name).
 - request_validator_key: key of a request_validators entry to attach.
 - request_parameters: map of "method.request.{location}.{name}" ->
 required (bool). e.g.
 { "method.request.querystring.id" = true }.
EOT
 type = map(object({
 resource_key = optional(string)
 http_method = string
 authorization = string
 authorizer_key = optional(string)
 authorization_scopes = optional(list(string), [])
 api_key_required = optional(bool, false)
 operation_name = optional(string)
 request_models = optional(map(string), {})
 request_validator_key = optional(string)
 request_parameters = optional(map(bool), {})
 }))
 default = {}

 validation {
 condition = alltrue([for k, v in var.methods: contains(["GET", "POST", "PUT", "DELETE", "HEAD", "OPTIONS", "ANY"], v.http_method)])
 error_message = "Each methods[*].http_method must be one of: GET, POST, PUT, DELETE, HEAD, OPTIONS, ANY."
 }

 validation {
 condition = alltrue([for k, v in var.methods: contains(["NONE", "CUSTOM", "AWS_IAM", "COGNITO_USER_POOLS"], v.authorization)])
 error_message = "Each methods[*].authorization must be one of: NONE, CUSTOM, AWS_IAM, COGNITO_USER_POOLS."
 }

 validation {
 condition = alltrue([for k, v in var.methods: v.authorization != "CUSTOM" || v.authorizer_key != null])
 error_message = "methods[*].authorizer_key is required when authorization is CUSTOM."
 }
}

variable "method_responses" {
 description = <<EOT
Map of method responses keyed by a stable name, each rendered as one
aws_api_gateway_method_response -- declares the shape of a response API
Gateway may return for a method (status code, headers, models).

 - method_key: key of the method (in methods) this response belongs to.
 - status_code: HTTP status code, e.g. "200".
 - response_models: map of content-type -> model name.
 - response_parameters: map of "method.response.header.{name}" -> required (bool).
EOT
 type = map(object({
 method_key = string
 status_code = string
 response_models = optional(map(string), {})
 response_parameters = optional(map(bool), {})
 }))
 default = {}
}

###############################################################################
# Integrations (backend wiring) -- for_each over map(object)
###############################################################################

variable "integrations" {
 description = <<EOT
Map of backend integrations keyed by a stable name, each rendered as one
aws_api_gateway_integration -- exactly one per method.

 - method_key: key of the method (in methods) this integration
 implements.
 - type: "MOCK", "AWS", "AWS_PROXY" (Lambda proxy), "HTTP",
 or "HTTP_PROXY".
 - integration_http_method: backend HTTP method. REQUIRED for AWS/AWS_PROXY/
 HTTP/HTTP_PROXY (Lambda invocations must use POST).
 - uri: backend URI. Required for AWS/AWS_PROXY/HTTP/
 HTTP_PROXY. Lambda invoke ARN
 (tf-mod-aws-lambda), HTTP(S) URL, or
 arn:aws:apigateway:{region}:{service}:{path|action}/...
 for AWS-service integrations.
 - integration_target: ALB/NLB ARN target for a VPC Link V2 private
 integration (uri sets the Host header instead).
 - credentials: IAM role ARN API Gateway assumes for an AWS
 integration, or "arn:aws:iam::*:user/*" to pass
 through the caller's identity. Wire from
 tf-mod-aws-iam-role.
 - connection_type: "INTERNET" (default) or "VPC_LINK" for a private
 integration through vpc_links.
 - vpc_link_key: key of a vpc_links entry (required when
 connection_type is VPC_LINK).
 - request_templates: map of content-type -> VTL mapping template.
 - request_parameters: map of "integration.request.{location}.{name}" ->
 source expression, e.g.
 { "integration.request.header.X-Foo" = "'Bar'" }.
 - passthrough_behavior: "WHEN_NO_MATCH" (default), "WHEN_NO_TEMPLATES",
 or "NEVER". Required when request_templates is set.
 - content_handling: "CONVERT_TO_BINARY" or "CONVERT_TO_TEXT".
 - timeout_milliseconds: backend timeout, 50-29000 (or up to 900000 for a
 STREAM response_transfer_mode). Default 29000.
 - cache_key_parameters: list of cache key parameters.
 - cache_namespace: integration cache namespace.
 - response_transfer_mode: "BUFFERED" (default) or "STREAM" (Lambda
 response streaming).
 - tls_config: { insecure_skip_verification = bool } for
 HTTP/HTTP_PROXY backends with private/self-signed
 certificates. Discouraged; document any use.
EOT
 type = map(object({
 method_key = string
 type = string
 integration_http_method = optional(string)
 uri = optional(string)
 integration_target = optional(string)
 credentials = optional(string)
 connection_type = optional(string, "INTERNET")
 vpc_link_key = optional(string)
 request_templates = optional(map(string), {})
 request_parameters = optional(map(string), {})
 passthrough_behavior = optional(string)
 content_handling = optional(string)
 timeout_milliseconds = optional(number, 29000)
 cache_key_parameters = optional(list(string), [])
 cache_namespace = optional(string)
 response_transfer_mode = optional(string, "BUFFERED")
 tls_config = optional(object({
 insecure_skip_verification = optional(bool, false)
 }))
 }))
 default = {}

 validation {
 condition = alltrue([for k, v in var.integrations: contains(["MOCK", "AWS", "AWS_PROXY", "HTTP", "HTTP_PROXY"], v.type)])
 error_message = "Each integrations[*].type must be one of: MOCK, AWS, AWS_PROXY, HTTP, HTTP_PROXY."
 }

 validation {
 condition = alltrue([for k, v in var.integrations: contains(["INTERNET", "VPC_LINK"], v.connection_type)])
 error_message = "Each integrations[*].connection_type must be one of: INTERNET, VPC_LINK."
 }

 validation {
 condition = alltrue([for k, v in var.integrations: v.connection_type != "VPC_LINK" || v.vpc_link_key != null])
 error_message = "integrations[*].vpc_link_key is required when connection_type is VPC_LINK."
 }
}

variable "integration_responses" {
 description = <<EOT
Map of integration responses keyed by a stable name, each rendered as one
aws_api_gateway_integration_response -- maps a backend response to a method
response.

 - method_key: key of the method (in methods) this belongs to.
 - status_code: the matching method_responses[*].status_code.
 - selection_pattern: regex matched against the backend response (Lambda
 error header, or HTTP status for other backends).
 Omit for the default response.
 - response_templates: map of content-type -> VTL mapping template.
 - response_parameters: map of "method.response.header.{name}" -> source
 expression, e.g.
 { "method.response.header.X-Foo" = "integration.response.header.X-Foo" }.
 - content_handling: "CONVERT_TO_BINARY" or "CONVERT_TO_TEXT".
EOT
 type = map(object({
 method_key = string
 status_code = string
 selection_pattern = optional(string)
 response_templates = optional(map(string), {})
 response_parameters = optional(map(string), {})
 content_handling = optional(string)
 }))
 default = {}
}

###############################################################################
# Gateway responses (error/4xx/5xx customization at the API level)
###############################################################################

variable "gateway_responses" {
 description = <<EOT
Map of gateway responses keyed by a stable name, each rendered as one
aws_api_gateway_gateway_response -- customizes API-Gateway-generated error
responses (auth failures, throttling, etc.), not backend responses.

 - response_type: e.g. "UNAUTHORIZED", "ACCESS_DENIED", "THROTTLED",
 "DEFAULT_4XX", "DEFAULT_5XX". See AWS docs for the
 full supported list.
 - status_code: HTTP status code override for this response.
 - response_templates: map of content-type -> VTL mapping template.
 - response_parameters: map of "gatewayresponse.header.{name}" -> value
 (static string literals must be single-quoted).
EOT
 type = map(object({
 response_type = string
 status_code = optional(string)
 response_templates = optional(map(string), {})
 response_parameters = optional(map(string), {})
 }))
 default = {}
}

###############################################################################
# Deployment (single resource; redeploys are hash-triggered)
#
# One aws_api_gateway_deployment.this per module call. Its `triggers` map is a
# sha1 hash over the caller-supplied resources/methods/integrations/etc. maps
# PLUS any extra values in deployment_trigger_resources, so any change to the
# API's shape forces a redeployment. create_before_destroy is always on (see
# main.tf) -- required to avoid "Active stages pointing to this deployment
# must be moved or deleted" on recreation.
###############################################################################

variable "deployment_description" {
 description = "Description of the deployment."
 type = string
 default = null
}

variable "deployment_trigger_resources" {
 description = <<EOT
Extra list of arbitrary strings folded into the deployment's redeployment
hash, on top of the automatic hash already computed from resources, methods,
integrations, integration_responses, method_responses, authorizers, models,
and gateway_responses. Use this to force a redeployment on something the
automatic hash does not see (e.g. an external file's content hash) or to add
filesha1() references for OpenAPI-adjacent assets consumed elsewhere.
EOT
 type = list(string)
 default = []
}

variable "deployment_variables" {
 description = "Map of stage variables to set on the deployment's initially-associated stage (rarely needed -- prefer stages[*].variables)."
 type = map(string)
 default = {}
}

###############################################################################
# Stages (child collection -- for_each over map(object))
#
# SECURE DEFAULT: xray_tracing_enabled defaults to true (observability
# baseline for a regulated FI). Every stage points at the single deployment
# resource above.
###############################################################################

variable "stages" {
 description = <<EOT
Map of stages keyed by a stable name, each rendered as one
aws_api_gateway_stage pointing at the module's single deployment. Referenced
by base_path_mappings / usage_plans / method_settings (stage_key) and
surfaced in the stage_arns / stage_invoke_urls outputs.

 - stage_name: stage path segment (e.g. "prod", "v1").
 - xray_tracing_enabled: SECURE DEFAULT true (observability
 baseline). Set false only with a documented
 exception.
 - access_log_destination_arn: CloudWatch Logs log group ARN (or Kinesis
 Firehose delivery stream beginning with
 "amazon-apigateway-") to receive access
 logs. Wire from tf-mod-aws-cloudwatch-log-group.
 Null (default) disables access logging --
 supply this for any production stage.
 - access_log_format: required alongside access_log_destination_arn;
 the log line format (JSON recommended).
 - cache_cluster_enabled: whether a stage cache cluster is enabled.
 Default false.
 - cache_cluster_size: one of 0.5, 1.6, 6.1, 13.5, 28.4, 58.2, 118, 237
 (GB). Required when cache_cluster_enabled.
 - client_certificate_key: key of a client_certificates entry to
 present to backend HTTP(S) integrations.
 - documentation_version: associated documentation_versions[*].version.
 - variables: map of stage variables.
 - canary_settings: optional canary deployment configuration
 { percent_traffic, stage_variable_overrides,
 use_stage_cache }. This module's single
 deployment resource is also used as the
 canary deployment_id target; for a true
 independent canary snapshot, manage a second
 deployment outside this module and reference
 its id via a stage override.
 - tags: extra tags merged over module tags for this stage.
EOT
 type = map(object({
 stage_name = string
 xray_tracing_enabled = optional(bool, true)
 access_log_destination_arn = optional(string)
 access_log_format = optional(string)
 cache_cluster_enabled = optional(bool, false)
 cache_cluster_size = optional(string)
 client_certificate_key = optional(string)
 documentation_version = optional(string)
 variables = optional(map(string), {})
 canary_settings = optional(object({
 percent_traffic = optional(number)
 stage_variable_overrides = optional(map(string), {})
 use_stage_cache = optional(bool, false)
 }))
 tags = optional(map(string), {})
 }))
 default = {}

 validation {
 condition = alltrue([for k, v in var.stages: v.access_log_destination_arn == null || v.access_log_format != null])
 error_message = "stages[*].access_log_format is required whenever access_log_destination_arn is set."
 }
}

variable "method_settings" {
 description = <<EOT
Map of per-stage method settings keyed by a stable name, each rendered as one
aws_api_gateway_method_settings. Managed separately from aws_api_gateway_stage
per the provider's own guidance (stages managed by aws_api_gateway_deployment's
legacy stage_name argument are recreated on redeploy; this module uses the
modern separated aws_api_gateway_stage resource, so this is safe).

 - stage_key: key of the stage (in stages) these settings apply to.
 - method_path: "{resource_path}/{http_method}" (leading slash trimmed) for
 one method, or "*/*" for every method in the stage.
 - settings: { metrics_enabled, logging_level ("OFF"|"ERROR"|"INFO"),
 data_trace_enabled, throttling_burst_limit,
 throttling_rate_limit, caching_enabled,
 cache_ttl_in_seconds, cache_data_encrypted,
 require_authorization_for_cache_control,
 unauthorized_cache_control_header_strategy }.
 SECURE DEFAULT: data_trace_enabled defaults to false
 (full request/response body logging can leak PII into
 CloudWatch Logs) -- opt in deliberately per method.
EOT
 type = map(object({
 stage_key = string
 method_path = string
 settings = optional(object({
 metrics_enabled = optional(bool, true)
 logging_level = optional(string, "ERROR")
 data_trace_enabled = optional(bool, false)
 throttling_burst_limit = optional(number)
 throttling_rate_limit = optional(number)
 caching_enabled = optional(bool, false)
 cache_ttl_in_seconds = optional(number)
 cache_data_encrypted = optional(bool, true)
 require_authorization_for_cache_control = optional(bool, true)
 unauthorized_cache_control_header_strategy = optional(string)
 }), {})
 }))
 default = {}

 validation {
 condition = alltrue([for k, v in var.method_settings: try(contains(["OFF", "ERROR", "INFO"], v.settings.logging_level), true)])
 error_message = "Each method_settings[*].settings.logging_level must be one of: OFF, ERROR, INFO."
 }
}

###############################################################################
# Client certificates (present to backend HTTP(S) integrations)
###############################################################################

variable "client_certificates" {
 description = <<EOT
Map of client certificates keyed by a stable name, each rendered as one
aws_api_gateway_client_certificate. Referenced by stages[*].client_certificate_key.

 - description: optional human-readable description.
EOT
 type = map(object({
 description = optional(string)
 }))
 default = {}
}

###############################################################################
# Custom domain names, private-domain access associations, and base path
# mappings
###############################################################################

variable "domain_names" {
 description = <<EOT
Map of custom domain names keyed by a stable name, each rendered as one
aws_api_gateway_domain_name. Referenced by base_path_mappings /
domain_name_access_associations (domain_name_key).

 - domain_name: fully-qualified domain name to register.
 - endpoint_configuration: { types = ["EDGE"] | ["REGIONAL"] | ["PRIVATE"],
 ip_address_type }. Must match the
 certificate you supply (EDGE
 certs live in us-east-1;
 REGIONAL certs live in this
 module's own Region).
 - certificate_arn: ACM cert ARN for an EDGE domain.
 MUST be requested in us-east-1
 (wire from a tf-mod-aws-acm
 call using providers = { aws =
 aws.us_east_1 }). Conflicts
 with regional_certificate_arn.
 - regional_certificate_arn: ACM cert ARN for a REGIONAL/
 PRIVATE domain, in the SAME
 Region as this module. Wire
 from a regional tf-mod-aws-acm
 call.
 - security_policy: TLS security policy, e.g.
 "TLS_1_2". Must be set for
 drift detection.
 - endpoint_access_mode: "BASIC" or "STRICT" -- only
 valid alongside a
 "SecurityPolicy_*"-prefixed
 security_policy.
 - mutual_tls_authentication: { truststore_uri (s3://...),
 truststore_version } for
 mTLS.
 - policy: resource policy scoping access
 to this domain name (PRIVATE
 domains only).
 - ownership_verification_certificate_arn: ACM-issued cert proving domain
 ownership (private-CA or mTLS
 imported certs).
 - tags: extra tags merged over module tags.
EOT
 type = map(object({
 domain_name = string
 endpoint_configuration = optional(object({
 types = optional(list(string), ["REGIONAL"])
 ip_address_type = optional(string)
 }), {})
 certificate_arn = optional(string)
 regional_certificate_arn = optional(string)
 security_policy = optional(string)
 endpoint_access_mode = optional(string)
 mutual_tls_authentication = optional(object({
 truststore_uri = string
 truststore_version = optional(string)
 }))
 policy = optional(string)
 ownership_verification_certificate_arn = optional(string)
 tags = optional(map(string), {})
 }))
 default = {}
}

variable "domain_name_access_associations" {
 description = <<EOT
Map of private-domain VPC endpoint access associations keyed by a stable
name, each rendered as one aws_api_gateway_domain_name_access_association.
Grants a VPC endpoint in ANOTHER account/VPC the ability to invoke a PRIVATE
custom domain name owned by this module.

 - domain_name_key: key of the domain_names entry (must be a
 PRIVATE endpoint_configuration).
 - access_association_source: VPC endpoint ID.
 - access_association_source_type: source type. Only "VPCE" is currently
 supported by the provider.
EOT
 type = map(object({
 domain_name_key = string
 access_association_source = string
 access_association_source_type = optional(string, "VPCE")
 }))
 default = {}
}

variable "base_path_mappings" {
 description = <<EOT
Map of base path mappings keyed by a stable name, each rendered as one
aws_api_gateway_base_path_mapping -- connects a custom domain name to this
API's deployed stage.

 - domain_name_key: key of the domain_names entry to attach to.
 - stage_key: key of the stages entry to expose. Null exposes every
 stage selectable by name in the path.
 - base_path: path segment prepended when calling via this domain.
 Null (default) exposes the API at the domain root.
EOT
 type = map(object({
 domain_name_key = string
 stage_key = optional(string)
 base_path = optional(string)
 }))
 default = {}
}

###############################################################################
# Usage plans, API keys, and usage-plan-key associations
###############################################################################

variable "usage_plans" {
 description = <<EOT
Map of usage plans keyed by a stable name, each rendered as one
aws_api_gateway_usage_plan -- meters/throttles API keys across one or more
stages. Referenced by usage_plan_keys (usage_plan_key).

 - name: usage plan name.
 - description: optional description.
 - product_code: AWS Marketplace product identifier (SaaS listings only).
 - api_stages: list of { stage_key, throttle = optional(list({
 path, burst_limit, rate_limit }), []) }. stage_key
 references this module's own stages map -- api_id is
 always this module's REST API.
 - quota_settings: { limit, offset, period ("DAY"|"WEEK"|"MONTH") }.
 - throttle_settings: { burst_limit, rate_limit } plan-wide defaults.
EOT
 type = map(object({
 name = string
 description = optional(string)
 product_code = optional(string)
 api_stages = optional(list(object({
 stage_key = string
 throttle = optional(list(object({
 path = string
 burst_limit = optional(number)
 rate_limit = optional(number)
 })), [])
 })), [])
 quota_settings = optional(object({
 limit = number
 offset = optional(number)
 period = string
 }))
 throttle_settings = optional(object({
 burst_limit = optional(number)
 rate_limit = optional(number)
 }))
 }))
 default = {}

 validation {
 condition = alltrue([for k, v in var.usage_plans: v.quota_settings == null || contains(["DAY", "WEEK", "MONTH"], v.quota_settings.period)])
 error_message = "Each usage_plans[*].quota_settings.period must be one of: DAY, WEEK, MONTH."
 }
}

variable "api_keys" {
 description = <<EOT
Map of API keys keyed by a stable name, each rendered as one
aws_api_gateway_api_key. An API key is USELESS without an associated usage
plan (usage_plan_keys) -- API Gateway requires a usage plan to actually
enforce/associate a key with a stage.

 - name: API key name.
 - description: optional description. Defaults to "Managed by Terraform".
 - enabled: whether the key can be used by callers. Default true.
 - value: caller-supplied key value (20-128 alphanumeric chars).
 Null (default) lets AWS generate one. SENSITIVE -- surfaced
 only in the sensitive api_key_values output.
 - customer_id: AWS Marketplace customer identifier (SaaS integrations).
EOT
 type = map(object({
 name = string
 description = optional(string)
 enabled = optional(bool, true)
 value = optional(string)
 customer_id = optional(string)
 }))
 default = {}
}

variable "usage_plan_keys" {
 description = <<EOT
Map of usage-plan/API-key associations keyed by a stable name, each rendered
as one aws_api_gateway_usage_plan_key.

 - usage_plan_key: key of a usage_plans entry.
 - api_key_key: key of an api_keys entry.
 - key_type: type of the key resource. Only "API_KEY" is currently
 supported by the provider. Default "API_KEY".
EOT
 type = map(object({
 usage_plan_key = string
 api_key_key = string
 key_type = optional(string, "API_KEY")
 }))
 default = {}
}

###############################################################################
# VPC Links (private integrations to an internal NLB)
###############################################################################

variable "vpc_links" {
 description = <<EOT
Map of API Gateway V1 VPC Links keyed by a stable name, each rendered as one
aws_api_gateway_vpc_link. Referenced by integrations[*].vpc_link_key
(connection_id) for a private HTTP/HTTP_PROXY integration to an internal
Network Load Balancer. FORCE-NEW: target_arns.

 - name: VPC Link name.
 - description: optional description.
 - target_arns: list of Network Load Balancer ARNs in the target VPC. AWS
 currently supports exactly one target. Wire from
 tf-mod-aws-lb (arn output, load_balancer_type = "network").
EOT
 type = map(object({
 name = string
 description = optional(string)
 target_arns = list(string)
 }))
 default = {}
}

###############################################################################
# Documentation (Swagger/OpenAPI export enrichment)
###############################################################################

variable "documentation_parts" {
 description = <<EOT
Map of documentation parts keyed by a stable name, each rendered as one
aws_api_gateway_documentation_part -- Swagger-compliant descriptions attached
to specific API entities, exported when generating an SDK/OpenAPI doc.

 - location: { type (e.g. "API", "METHOD", "REQUEST_BODY", "RESOURCE"),
 method (default "*"), name, path (default "/"),
 status_code (default "*") }.
 - properties: JSON-encoded string of description key/value pairs, e.g.
 jsonencode({ description = "..." }).
EOT
 type = map(object({
 location = object({
 type = string
 method = optional(string)
 name = optional(string)
 path = optional(string)
 status_code = optional(string)
 })
 properties = string
 }))
 default = {}
}

variable "documentation_versions" {
 description = <<EOT
Map of documentation version snapshots keyed by a stable name, each rendered
as one aws_api_gateway_documentation_version. Create documentation_parts
first (via depends_on / implicit reference) -- a version snapshots whatever
parts exist at apply time.

 - version: version identifier string.
 - description: optional description.
EOT
 type = map(object({
 version = string
 description = optional(string)
 }))
 default = {}
}

###############################################################################
# Account settings (region-wide singleton -- opt-in, off by default)
#
# aws_api_gateway_account is scoped to the WHOLE AWS account + Region, not to
# this REST API. Enabling it here is appropriate only for the single module
# call that owns account-wide API Gateway CloudWatch logging role wiring; a
# second module call in the same account/Region with manage_account_settings
# = true will fight over the same singleton. See SCOPE.md AWS Prerequisites.
###############################################################################

variable "manage_account_settings" {
 description = <<EOT
Whether this module call manages the account-wide aws_api_gateway_account
singleton (CloudWatch role for API Gateway logging). Defaults to false --
only ONE module call per account/Region should ever set this true. Leave
false and manage account settings via a single dedicated call (or manually)
in shared/platform infrastructure.
EOT
 type = bool
 default = false
}

variable "account_cloudwatch_role_arn" {
 description = <<EOT
IAM role ARN API Gateway assumes to write CloudWatch Logs/metrics at the
account level. Required when manage_account_settings is true. Wire from
tf-mod-aws-iam-role (a role trusting apigateway.amazonaws.com with
CloudWatch Logs write permissions).
EOT
 type = string
 default = null

 validation {
 condition = !var.manage_account_settings || var.account_cloudwatch_role_arn != null
 error_message = "account_cloudwatch_role_arn is required when manage_account_settings is true."
 }
}

###############################################################################
# Universal tail
###############################################################################

variable "tags" {
 description = <<EOT
A map of tags to assign to all taggable resources created by this module (the
REST API, API keys, client certificates, domain names, usage plans, VPC
links, and stages). These merge with provider-level default_tags; resource
tags win on key conflict. Per-item tags on stages/domain_names merge over
this map. The computed tags_all output reflects the merged set on the REST
API. Not every child resource in this family is taggable (resources, methods,
integrations, models, authorizers, deployments, base path mappings,
documentation parts/versions, and gateway responses accept no tags).
EOT
 type = map(string)
 default = {}
}

variable "timeouts" {
 description = <<EOT
Optional Terraform operation timeouts. Only aws_api_gateway_domain_name
supports a timeouts block in this provider version (create/update -- custom
domain name propagation, e.g. through CloudFront for EDGE domains, can take
up to 60m); delete is accepted here for forward compatibility but currently
has no effect. Every other resource in this family (rest_api, resources,
methods, integrations, deployment, stages,...) has no configurable timeout.
EOT
 type = object({
 create = optional(string)
 update = optional(string)
 delete = optional(string)
 })
 default = {}
}
