# tf-mod-aws-api-gateway — SCOPE

Composite module for an Amazon API Gateway **V1 REST API** (the original
resource/method/integration model, as distinct from V2 HTTP/WebSocket APIs in
the sibling `tf-mod-aws-api-gateway-v2`). It owns the REST API, its resource
tree, methods, integrations, authorizers, models, deployment, stages, custom
domain names, usage plans/API keys, VPC Links, gateway responses, client
certificates, and documentation artifacts — so a single module call produces a
complete, X-Ray-traced, REGIONAL-by-default REST API aligned with the Casey's
baseline.

- **Module type:** Composite
- **Primary resource (keystone):** `aws_api_gateway_rest_api.this`

## In-scope resources

The module manages the following (allow-list) — 25 resource types, all
`for_each` over `map(object(...))` except the keystone, the deployment, and
two conditional singletons rendered via a 0/1-entry `for_each` map (never
`count`):

- `aws_api_gateway_rest_api` — keystone
- `aws_api_gateway_rest_api_policy` — resource policy, conditional singleton (`var.policy != null`)
- `aws_api_gateway_resource` — URL path tree (self-referential `parent_id`)
- `aws_api_gateway_model` — JSON Schema request/response models
- `aws_api_gateway_request_validator` — request body/parameter validation
- `aws_api_gateway_authorizer` — Lambda TOKEN/REQUEST or Cognito authorizers
- `aws_api_gateway_method` — HTTP methods on resources
- `aws_api_gateway_method_response` — declared response shapes per method
- `aws_api_gateway_integration` — backend wiring per method
- `aws_api_gateway_integration_response` — backend-response-to-method-response mapping
- `aws_api_gateway_gateway_response` — API-Gateway-generated error customization
- `aws_api_gateway_deployment` — single resource; hash-triggered redeployment
- `aws_api_gateway_stage` — one or more named references to the deployment
- `aws_api_gateway_method_settings` — per-stage/per-method logging, metrics, throttling, caching
- `aws_api_gateway_client_certificate` — presented to backend HTTP(S) integrations
- `aws_api_gateway_domain_name` — custom domain registration (EDGE/REGIONAL/PRIVATE)
- `aws_api_gateway_domain_name_access_association` — cross-account VPC endpoint access to a PRIVATE domain
- `aws_api_gateway_base_path_mapping` — connects a custom domain to a stage
- `aws_api_gateway_usage_plan` — API-key metering/throttling across stages
- `aws_api_gateway_api_key` — API keys
- `aws_api_gateway_usage_plan_key` — key-to-usage-plan association
- `aws_api_gateway_vpc_link` — private integration bridge to an internal NLB
- `aws_api_gateway_documentation_part` — Swagger/OpenAPI-export documentation
- `aws_api_gateway_documentation_version` — documentation snapshot
- `aws_api_gateway_account` — account/Region-wide CloudWatch role setting, conditional singleton (`var.manage_account_settings`)

This is the largest resource-block count in the Casey's AWS library (25, versus
`tf-mod-aws-vpc`'s previous high of 21) — still comfortably under the
35-resource-type ceiling in `resource_block_module_matrix.md`.

## Out-of-scope resources (consumed by reference, or deliberately excluded)

- **`aws_api_gateway_rest_api_put`** — deliberately excluded by design. This
  resource (and the `body` argument on `aws_api_gateway_rest_api` itself)
  drives the REST API from an OpenAPI/Swagger document; the provider's own
  documentation warns that mixing a `body`-driven API with Terraform-managed
  `aws_api_gateway_resource` / `method` / `integration` / `model` /
  `gateway_response` resources causes updates to one to silently overwrite the
  other. This module commits to the native Terraform resource graph
  (resources/methods/integrations maps) as its one supported authoring style.
  A caller who wants an OpenAPI-driven REST API should compose
  `aws_api_gateway_rest_api_put` directly against this module's `id` output,
  in a separate, non-graph-based module call — never both in the same call.
- Lambda function — `uri` / `authorizer_uri` (invoke ARN) from `tf-mod-aws-lambda`
- ACM certificate(s) — `certificate_arn` / `regional_certificate_arn` (from `tf-mod-aws-acm`)
- VPC link target (NLB) — `vpc_links[*].target_arns` (from `tf-mod-aws-lb`, `load_balancer_type = "network"`)
- Cognito user pool — `authorizers[*].provider_arns` (from `tf-mod-aws-cognito`) for `COGNITO_USER_POOLS` authorizers
- WAFv2 web ACL — associated to a stage by ARN, managed in `tf-mod-aws-wafv2` (this module only surfaces `stage_web_acl_arns` for drift visibility)
- VPC endpoint(s) — `endpoint_configuration.vpc_endpoint_ids` / `domain_name_access_associations[*].access_association_source` (from `tf-mod-aws-vpc-endpoint`)
- CloudWatch Logs log group — `stages[*].access_log_destination_arn` (from `tf-mod-aws-cloudwatch-log-group`)
- IAM role(s) — `authorizers[*].authorizer_credentials`, `integrations[*].credentials`, `account_cloudwatch_role_arn` (from `tf-mod-aws-iam-role`)
- Route 53 records for a custom domain name — created in `tf-mod-aws-route53-zone` against this module's `domain_name_regional_domain_names` / `domain_name_cloudfront_domain_names` outputs

## Consumes

| Input | Type | Source module |
|---|---|---|
| `endpoint_configuration.vpc_endpoint_ids` | `list(string)` | `tf-mod-aws-vpc-endpoint` |
| `authorizers[*].authorizer_uri` | `string` (Lambda invoke ARN) | `tf-mod-aws-lambda` |
| `authorizers[*].authorizer_credentials` | `string` (IAM role ARN) | `tf-mod-aws-iam-role` |
| `authorizers[*].provider_arns` | `list(string)` (Cognito user pool ARNs) | `tf-mod-aws-cognito` |
| `integrations[*].uri` | `string` (Lambda invoke ARN / HTTP(S) URL / AWS service URI) | `tf-mod-aws-lambda` / external |
| `integrations[*].credentials` | `string` (IAM role ARN) | `tf-mod-aws-iam-role` |
| `vpc_links[*].target_arns` | `list(string)` (NLB ARN) | `tf-mod-aws-lb` |
| `domain_names[*].certificate_arn` | `string` (ACM cert ARN, us-east-1 for EDGE) | `tf-mod-aws-acm` |
| `domain_names[*].regional_certificate_arn` | `string` (ACM cert ARN, same Region) | `tf-mod-aws-acm` |
| `domain_name_access_associations[*].access_association_source` | `string` (VPC endpoint id) | `tf-mod-aws-vpc-endpoint` |
| `stages[*].access_log_destination_arn` | `string` (CloudWatch log group ARN) | `tf-mod-aws-cloudwatch-log-group` |
| `account_cloudwatch_role_arn` | `string` (IAM role ARN) | `tf-mod-aws-iam-role` |

## Required IAM permissions

Least-privilege actions the Terraform identity needs:

| Action | Required for |
|---|---|
| `apigateway:GET`, `apigateway:POST`, `apigateway:PUT`, `apigateway:PATCH`, `apigateway:DELETE` on `arn:aws:apigateway:*::/restapis*` | Full lifecycle of the REST API and every child resource in this module (API Gateway authorizes by HTTP verb against resource-path ARNs, not fine-grained action names) |
| `apigateway:POST`, `apigateway:PATCH` on `/restapis/*/deployments*` and `/restapis/*/stages*` | Deployment and stage lifecycle |
| `apigateway:POST` on `/usageplans*`, `/apikeys*` | Usage plan / API key lifecycle |
| `apigateway:POST` on `/domainnames*`, `/domainnameaccessassociations*`, `/restapis/*/basepathmappings*` | Custom domain and base path mapping lifecycle |
| `apigateway:POST` on `/vpclinks*` | VPC Link lifecycle |
| `apigateway:PATCH` on `/account` | Account settings (only when `manage_account_settings = true`) |
| `iam:PassRole` on the authorizer / integration / account CloudWatch role ARNs | Passing an IAM role to API Gateway for Lambda authorizer invocation, AWS-service integrations, or account-level CloudWatch logging |
| `lambda:GetFunction`, `lambda:AddPermission` | Confirming and authorizing Lambda invocation by API Gateway for `AWS_PROXY` integrations and Lambda authorizers (a companion `aws_lambda_permission` is created by the caller / `tf-mod-aws-lambda`, not this module) |
| `acm:DescribeCertificate` | Resolving domain name certificates |
| `ec2:DescribeVpcEndpoints` | Resolving PRIVATE endpoint VPC endpoint IDs |
| `elasticloadbalancing:DescribeLoadBalancers` | Resolving VPC Link target NLB ARNs |

> API Gateway's IAM action namespace is HTTP-verb-based
> (`apigateway:GET|POST|PUT|PATCH|DELETE`) scoped to resource-path ARNs
> (`arn:aws:apigateway:<region>::/restapis/<id>/...`), not per-resource-type
> action names like most other AWS services — least privilege here means
> scoping the resource-path patterns, not the verb list.

## AWS Prerequisites

- **No service-linked role** is required for API Gateway itself.
- **Account-level CloudWatch logging role (singleton):** `aws_api_gateway_account`
  is scoped to the WHOLE account + Region, not to this REST API. Only ONE
  module call per account/Region should set `manage_account_settings = true`;
  every other call must leave it `false` (default). Attempting to manage it
  from two module calls in the same account/Region causes permanent drift/
  fighting.
- **Custom domain names:** an EDGE-optimized domain requires an ACM
  certificate in **us-east-1** (API Gateway provisions an AWS-managed
  CloudFront distribution behind it); a REGIONAL or PRIVATE domain requires
  the certificate in the **same Region** as this module. This is the one
  us-east-1 touchpoint in this module family — document clearly per domain.
- **PRIVATE APIs** require at least one interface VPC endpoint for
  `com.amazonaws.<region>.execute-api` (from `tf-mod-aws-vpc-endpoint`) AND a
  resource policy (`var.policy`) scoping `execute-api:Invoke` to that VPC
  endpoint — a PRIVATE API with no policy is unreachable by design (safe
  failure mode) but also useless; both must be wired together.
- **Usage plans require stages to already exist** — API Gateway rejects a
  usage plan referencing a stage that hasn't been deployed yet; this module
  handles the ordering internally via resource references.
- **Quotas:** default 600 REST APIs per account/Region; 300 resources per API;
  10 authorizers per API; 60 requests/second account-level throttle (soft,
  raisable); 500 usage plans per account; most raisable via Service Quotas.

## Emits

| Output | Description | Consumed by |
|---|---|---|
| `id` | REST API id | tagging, cross-references |
| `arn` | REST API ARN — cross-resource reference type | IAM policies, audit |
| `name` | REST API name | tagging, audit |
| `root_resource_id` | Root ("/") resource id | external `aws_api_gateway_resource` additions |
| `execution_arn` | `execute-api` ARN base | `aws_lambda_permission.source_arn` (`tf-mod-aws-lambda`) |
| `resource_ids` / `resource_paths` | Map of resources key → id / full path | audit, external method wiring |
| `method_ids` | Map of methods key → `"<resource_id>/<http_method>"` | audit |
| `authorizer_ids` / `model_ids` / `request_validator_ids` | Maps of key → id | audit, external references |
| `deployment_id` | The module's single deployment id | audit |
| `stage_ids` / `stage_arns` / `stage_invoke_urls` / `stage_execution_arns` | Maps of stages key → id/ARN/invoke URL/execution ARN | `tf-mod-aws-lambda` (per-stage permission), app config, monitoring |
| `stage_web_acl_arns` | Map of stages key → associated WAFv2 web ACL ARN (null until associated) | `tf-mod-aws-wafv2` drift visibility |
| `domain_name_ids` / `domain_name_arns` | Maps of domain_names key → id/ARN | audit |
| `domain_name_cloudfront_domain_names` / `domain_name_regional_domain_names` / `domain_name_regional_zone_ids` | Alias targets for a Route 53 record | `tf-mod-aws-route53-zone` |
| `usage_plan_ids` / `usage_plan_arns` | Maps of usage_plans key → id/ARN | billing/SaaS integrations |
| `api_key_ids` / `api_key_arns` | Maps of api_keys key → id/ARN | audit |
| `api_key_values` | Map of api_keys key → key value. **SENSITIVE.** | caller distribution (out of band, never logged) |
| `vpc_link_ids` | Map of vpc_links key → id | audit |
| `client_certificate_ids` / `client_certificate_arns` | Maps of client_certificates key → id/ARN | audit |
| `tags_all` | All tags incl. provider `default_tags` | governance/audit |

## Provider gotchas

- **The deployment MUST use `create_before_destroy = true`.** Without it,
  recreating the deployment fails with `BadRequestException: Active stages
  pointing to this deployment must be moved or deleted` — this module bakes
  it in unconditionally.
- **`aws_api_gateway_method` / `_method_response` / `_integration` /
  `_integration_response` have no independent `id`.** They are addressed by
  the composite key `(rest_api_id, resource_id, http_method[, status_code])`.
  This module resolves `resource_id`/`http_method` from the referenced
  `methods[*]` map entry rather than exposing a synthetic id.
- **`triggers` on the deployment only capture VALUE changes you list**, not
  automatic dependency ordering — this module both hashes the relevant
  variable maps into `triggers.redeployment` AND sets explicit `depends_on`
  against every child resource type, per the provider's own recommendation.
- **`aws_api_gateway_vpc_link.target_arns` is FORCE-NEW.**
- **Usage plan `api_stages` requires the stage to exist first** — ordered
  automatically via the `aws_api_gateway_stage` resource reference.
- **Access logging on a stage requires BOTH `destination_arn` and `format`**
  — supplying only one is a plan-time validation error in this module.
- **PRIVATE APIs and `disable_execute_api_endpoint`** — disabling the default
  execute-api endpoint before a working custom domain name is fully wired
  (DNS + base path mapping) locks out every caller; sequence carefully.
- **EDGE custom domain certificates live in us-east-1; REGIONAL/PRIVATE
  certificates live in this module's own Region** — the one us-east-1
  touchpoint in this otherwise fully regional module family.
- **`tags` vs `tags_all`.** `var.tags` flows to every taggable resource in
  this family (REST API, API keys, client certificates, domain names, usage
  plans, VPC links, stages); `tags_all` is the computed merge over provider
  `default_tags` (resource tags win), surfaced only on the REST API itself.
  Not every resource in this family accepts tags (resources, methods,
  integrations, models, authorizers, deployments, base path mappings,
  documentation parts/versions, and gateway responses do not).
- **Destroy ordering:** usage plan keys → usage plans/API keys → base path
  mappings → domain names → stages → deployment → integration responses/
  integrations → method responses/methods → resources → REST API. Terraform
  sequences this automatically via the resource references in this module;
  the `create_before_destroy` deployment lifecycle changes the create-side
  ordering but not the destroy-side ordering.

## Secure-by-default decisions

| Posture | Default | Opt-out |
|---|---|---|
| Endpoint type | `endpoint_configuration.types = ["REGIONAL"]` (NOT AWS's own implicit `["EDGE"]`) | set `["EDGE"]` or `["PRIVATE"]` deliberately |
| Method authorization | **no default — required per method**, forcing an explicit choice every time (never silently `"NONE"`) | caller must still type `"NONE"` explicitly for an intentionally open method |
| Stage tracing | `stages[*].xray_tracing_enabled = true` | set `false` per stage (discouraged) |
| Method-settings data trace | `method_settings[*].settings.data_trace_enabled = false` | set `true` deliberately (full req/resp body logging can leak NPI into CloudWatch Logs) |
| Method-settings cache encryption | `cache_data_encrypted = true` when caching is enabled | set `false` (discouraged) |
| Method-settings cache-control auth | `require_authorization_for_cache_control = true` | set `false` (discouraged) |
| Default execute-api endpoint | left enabled (`disable_execute_api_endpoint = false`) until a custom domain is proven working | `true` once DNS + base path mapping are confirmed |
| Account CloudWatch role | opt-in singleton (`manage_account_settings = false` by default) | `true` in exactly one shared/platform module call |

## Design decisions

- One composite owns the full V1 REST API surface — resource tree, methods,
  integrations, auth, models, deployment, stages, domains, usage plans, VPC
  Links, and documentation — so a caller gets a complete, deployable REST API
  from a single module call, mirroring the `tf-mod-aws-lb` design philosophy
  applied to a much deeper, self-referential resource tree.
- Every child collection is `for_each` over `map(object(...))` keyed by a
  stable caller string — no `count` anywhere, including the two conditional
  singletons (`aws_api_gateway_rest_api_policy`, `aws_api_gateway_account`),
  which use a 0/1-entry `for_each` map instead.
- The resource tree (`aws_api_gateway_resource`) is intentionally
  self-referential: each entry's `parent_key` may reference any other key in
  the same map, letting Terraform resolve the correct dependency graph
  without the caller managing path ordering by hand.
- The module manages exactly ONE deployment resource and lets `stages[*]`
  fan out from it. This keeps the redeploy-hash design simple and matches
  this module's Terraform-native (not OpenAPI-body) authoring style. True
  blue/green canary deployments (a second, independent deployment snapshot)
  are out of scope for a single module call — compose two calls or extend the
  deployment to a keyed map in a future major version if that pattern becomes
  common.
- The OpenAPI/Swagger `body`-import authoring style
  (`aws_api_gateway_rest_api_put`, the `body` argument) is deliberately
  excluded — see "Out-of-scope resources" above.
- WAFv2 web ACL association happens in `tf-mod-aws-wafv2` (by stage ARN), and
  Lambda permissions in `tf-mod-aws-lambda` (by `execution_arn`), keeping this
  module's blast radius to the API Gateway objects themselves.
