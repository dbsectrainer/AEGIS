# Terraform security review

## Reproducing the scans

Run from the repository root:

```sh
terraform fmt -recursive -check terraform
cd terraform/environments/production/southeast
terraform init -backend=false -input=false
terraform validate
terraform test -verbose
cd -

trivy config --severity HIGH,CRITICAL terraform
tfsec terraform --force-all-dirs --minimum-severity HIGH
checkov -d terraform --quiet --compact
```

The recorded results are in `docs/evidence/build-results/` and
`docs/evidence/test-results/`.

## Current result (2026-10-31)

| Gate | Result |
| --- | --- |
| `terraform fmt -recursive -check` | Passed |
| `terraform init -backend=false` + `validate` | Passed; no warnings |
| `terraform test` (mock providers) | 2 passed, 0 failed; full plan 164 resources |
| Trivy HIGH/CRITICAL | 0 findings |
| tfsec HIGH/CRITICAL | 0 findings; 106 passed, 169 documented ignores |
| Checkov | 343 passed, 34 failed, 0 skipped (advisory) |

The Terraform root now declares all three providers explicitly, uses declared
variables, no longer carries placeholder inputs in a tracked `terraform.tfvars`,
and no longer emits undeclared-variable warnings.

**No live plan or apply was run.** Mock-provider plans validate wiring and schema;
they do not prove provider API behavior, IAM permissions, resource creation, or
runtime control effectiveness.

## High findings and exceptions

- **Flow-log IAM policy:** CloudWatch Logs delivery requires a log-stream
  wildcard. The policy is scoped to the dedicated flow-log group ARN and carries
  `tfsec:ignore:AVD-AWS-0057` with that rationale.
- **EKS KMS role policy:** Actions are enumerated (`Encrypt`, `Decrypt`,
  `ReEncryptFrom`, `ReEncryptTo`, the `GenerateDataKey*` family, `CreateGrant`,
  `DescribeKey`) rather than wildcarded.
- **KMS key policy wildcards:** Checkov flags `Resource = "*"` in KMS key
  policies. AWS KMS key policies apply to the key itself and use `"*"` for the
  key-policy statements; the remaining findings are documented in the advisory
  log rather than suppressed wholesale.
- **GKE master authorized networks (CKV_GCP_20):** the cluster uses a
  private endpoint. API access is restricted to the VPC, so a public
  authorized-networks configuration is not applicable. The tfsec check is
  suppressed with that rationale; the Checkov finding remains visible in the
  advisory log for explicit acceptance.
- **Cloud SQL TLS:** `ssl_mode = "ENCRYPTED_ONLY"` requires TLS. The existing
  tfsec exception targets the legacy `require_ssl` check, which does not
  recognize `ssl_mode`.
- **GKE PSP:** PSP was removed in GKE 1.25; the exception remains and Pod
  Security Admission must be configured on workload namespaces separately.
- **GKE metadata:** Node pools use `GKE_METADATA`; the tfsec boolean-coercion
  check is satisfied.
- **Spanner deletion protection:** `deletion_protection = true` is set; Checkov
  still reports the finding. This is a scanner false positive to re-check when
  the provider/policy is updated.

## Fixes applied during this review

- Explicit AWS, AzureRM (`usgovernment`), Google, and TLS providers.
- Managed Azure resource group and service-specific private DNS zones for SQL
  (`privatelink.database.usgovcloudapi.net`) and Cosmos DB
  (`privatelink.documents.azure.us`).
- A managed AWS KMS key with an EKS identity policy; removed the placeholder KMS
  ARN.
- AWS VPC flow logs, a restricted default security group, gateway endpoint route
  associations, and interface endpoints for ECR, STS, logs, EC2, SSM, KMS, EKS,
  load balancing, autoscaling, monitoring, and Secrets Manager.
- AWS node security group attached through a launch template; SSH remote access
  removed.
- Azure NAT gateway associated with private subnets; AKS subnet delegation
  removed; private endpoints enabled for SQL and Cosmos.
- Azure SQL private networking, TLS 1.2, AD-only authentication, extended
  vulnerability assessment metadata, and user-assigned identity fixed.
- Cosmos DB public network access and local authentication disabled.
- AKS local admin disabled, Standard tier, node autoscaling without conflicting
  `node_count`, critical-only system pool, and Standard load balancer SKU fixed.
- GKE node pools no longer set `node_count` with autoscaling; required APIs,
  BigQuery dataset, artifact registry, and GKE backup plan dependencies added.
- Cloud SQL private range now references the allocated range **name**, and
  database logging/audit flags were added.
- GCP duplicate service-networking ownership was removed from the networking
  module for the production root.

## Before applying

- **Azure AKS/ACR egress:** the private NSG denies internet egress, ACR is still
  publicly reachable with IP restrictions, and AKS system components may require
  `mcr.microsoft.com`/Azure service access. Add a reviewed firewall or private
  endpoints and validate image pulls. Do not treat the current stack as
  production-ready.
- **Azure SQL auditing:** Checkov still requests storage-backed auditing and
  vulnerability assessment. Add an approved storage account and retention policy
  if required by the authorization boundary.
- **Checkov advisory:** 34 findings remain, including ACR zone redundancy/signed
  images/quarantine, Cosmos CMEK, AWS Backup for RDS, RDS query logging, and
  CloudWatch Logs KMS encryption. Resolve or formally accept each before ATO.
- **AWS interface endpoints:** service availability and private DNS behavior in
  GovCloud must be verified in the target account. Endpoint policies should be
  reviewed for least privilege.
- **Remote state:** the S3 bucket and DynamoDB table referenced by the backend do
  not exist in this environment. Provision them with access logging, encryption,
  and least-privilege bucket policy before `make init`.
- **Live plan/apply:** run in a non-production account first, with separate state,
  cost controls, and rollback procedures.
