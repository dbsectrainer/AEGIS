# Terraform security review

## Reproducing the scan

Run from the repository root with tfsec v1.28.14:

```sh
tfsec terraform --force-all-dirs --minimum-severity HIGH
tfsec terraform/environments/production/southeast --minimum-severity HIGH
```

The first command covers standalone modules and providers as well as the production
root. Findings may appear twice when a module is also scanned through its caller.
Without `--force-all-dirs`, scanning `terraform` can return no findings because that
directory contains no Terraform files itself. The compliance scanning script uses
this option for both JSON and SARIF output.

After this review, both commands report zero active high or critical findings.
Medium and low findings remain unresolved. A successful scan is not proof of
deployment readiness.

`terraform fmt -recursive -check terraform`, shell syntax checking of the scanning
script, and production-root `terraform validate` also pass. Validation still warns
about existing entries in `terraform.tfvars` that have no matching root variables;
those values are ignored and should be reconciled before relying on them for a
deployment. No state-backed plan or apply was run.

## High findings and exceptions

- **SSM IAM:** Parameter reads are limited to the provider's partition, region and
  account, under `/${var.environment}/*`. The trailing wildcard covers parameter
  names within that environment. `DescribeParameters` was removed: it requires
  `Resource = "*"` and was not authorized by the previous parameter ARN either.
  Account-wide parameter discovery is not granted to the ECS instance role.
- **GKE metadata:** Both node pools use the boolean `true` for
  `disable-legacy-endpoints`. Terraform coerces it to the provider's string-valued
  metadata map, while tfsec recognizes the boolean. Both checks pass with ignores
  disabled; Workload Identity metadata mode remains `GKE_METADATA`.
- **Cloud SQL TLS:** `ssl_mode = "ENCRYPTED_ONLY"` requires TLS. The tfsec exception
  is attached to `ip_configuration`, the block reported by the scanner. tfsec
  v1.28.14 checks the legacy `require_ssl` field; do not add that field solely to
  satisfy the scanner. Revisit the exception when the scanner supports `ssl_mode`,
  and review it whenever changing this block. Existing plaintext sessions must be
  closed for TLS enforcement to cover all sessions.
- **GKE PSP:** The cluster-level exception remains because PSP was removed in GKE
  1.25. Security posture scanning does not enforce pod admission policy. This
  repository does not configure Pod Security Admission namespace labels; choose
  and enforce the appropriate Pod Security Standards before deploying workloads.

References: [Cloud SQL TLS](https://docs.cloud.google.com/sql/docs/postgres/configure-ssl-instance),
[tfsec metadata check](https://aquasecurity.github.io/tfsec/latest/checks/google/gke/metadata-endpoints-disabled/),
[GKE PSP removal](https://docs.cloud.google.com/kubernetes-engine/docs/deprecations/podsecuritypolicy),
[Pod Security Admission](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/podsecurityadmission).

## Before applying

- **AKS:** In the pinned AzureRM v4.81.0 provider, changing
  `private_cluster_enabled` forces replacement. Review a plan against the actual
  state and schedule migration before applying to an existing cluster. Prepare
  private API connectivity and DNS resolution for operators and deployment runners
  through a jump host, VPN, or connected network. This review did not apply changes.
- **AWS:** The networking module has NAT gateways and default routes, but compute
  security groups only allow egress to private subnet CIDRs. NAT does not bypass
  those restrictions. ECR, STS, ECS and other public service endpoints therefore
  remain inaccessible through these rules. Provision the required interface
  endpoints with private DNS and reachable endpoint security groups, and authorize
  S3/DynamoDB prefix-list traffic for gateway endpoints as needed. The existing
  gateway endpoints also need private route-table associations. Inventory image
  pulls, agent registration, logging, secrets, identity and application traffic;
  verify startup and operation before rollout. General external access needs a
  separately reviewed egress design.
- **Azure ingress:** `public_ingress_source_prefixes` defaults to
  `["VirtualNetwork"]`, so ordinary public HTTPS clients are blocked. Pass approved
  CIDRs or one service tag in the environment's `azure_networking` module call.
  The module uses `source_address_prefix` for a single value and
  `source_address_prefixes` for multiple CIDRs, because Azure forbids service tags
  in the plural field. Verify service-tag availability in the target sovereign
  cloud before choosing a Front Door tag. Do not assume commercial-cloud tag or
  service availability in Azure Government.

References: [pinned AKS schema](https://github.com/hashicorp/terraform-provider-azurerm/blob/v4.81.0/internal/services/containers/kubernetes_cluster_resource.go),
[pinned NSG documentation](https://github.com/hashicorp/terraform-provider-azurerm/blob/v4.81.0/website/docs/r/network_security_group.html.markdown).
