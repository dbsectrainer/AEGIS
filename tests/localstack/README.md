# Local AWS Emulation

This directory contains a LocalStack-based integration test for AWS Terraform
patterns. It creates real AWS provider resources in an emulator and verifies them
through the AWS CLI — no cloud account is used.

## What is tested

`run-localstack-tests.sh` starts (or reuses) a LocalStack container, applies the
fixture in `terraform/`, and asserts:

- S3 bucket, versioning, AES256 encryption, public-access block, object upload/download
- DynamoDB table, billing mode, put/get item
- SQS queue and SNS-to-SQS message delivery
- KMS key alias
- CloudWatch Logs group and retention
- IAM role and inline policy
- EC2 VPC, two subnets, and security group

It also destroys the fixture and writes evidence to
`docs/evidence/localstack/`.

## Commands

```bash
# Full run: start LocalStack, apply, verify, destroy
make test-localstack

# Already-running LocalStack (useful in CI service containers)
tests/localstack/run-localstack-tests.sh --no-start

# Leave resources for debugging
tests/localstack/run-localstack-tests.sh --keep
```

Requirements: Docker, Terraform 1.12+, AWS CLI, `jq`, `curl`.

The fixture pins **Terraform AWS provider 5.x** because LocalStack 4.4.0
community does not reliably complete DynamoDB table update waiters with provider
6.x. The production root remains on provider 6.x. This test therefore validates
provider behavior and the local toolchain, not the production provider version.

## Coverage boundaries

LocalStack community is useful for supported, API-shaped services but is not a
GovCloud or managed-Kubernetes emulator. The following remain unverified here:

- GovCloud partitions, endpoints, and IAM policy ARNs
- EKS, ECS, RDS/Aurora, and other managed services
- Azure and GCP resources
- Production module IAM managed-policy attachments
- Live IAM permissions, quotas, networking, and cost behavior

## Review of the suggested local-testing options

| Option | Fit for AEGIS | Decision |
| --- | --- | --- |
| LocalStack | Best fit for AWS provider/Terraform CRUD across supported services | Implemented |
| AWS SAM CLI | No Lambda functions or API Gateway definitions exist in this repository | Not applicable |
| Moto | No Python AWS SDK application code to intercept; Terraform is the subject | Not used |
| DynamoDB Local | LocalStack already covers basic DynamoDB CRUD; the production table's SSE/PITR update path failed with provider 6.x + LocalStack 4.4.0 | Not added separately |
| MinIO | No S3-consuming application; LocalStack verifies the S3 API/Terraform path | Not added separately |
| ElasticMQ | No SQS resources in the production stack; LocalStack covers SQS/SNS delivery | Not added separately |
| AWS sandbox accounts / Skill Builder | The only way to validate real GovCloud, EKS/ECS/RDS, IAM, and provider 6.x behavior | Recommended next step; unavailable in this audit |
| Azure/GCP emulators | Azurite is storage-only; GCP emulators do not emulate AKS/GKE or managed databases | Not a substitute for live validation |

## Why the production modules are not applied here

The production AWS modules include GovCloud-specific managed-policy ARNs, EKS,
ECS, RDS/Aurora, VPC endpoints, and flow logs. LocalStack 4.4.0 community does not
support all of them, and applying a reduced copy would not prove the production
modules. Their wiring is covered by `terraform test` with mock providers; real
provider behavior remains a sandbox/live-account task.
