# Local AWS Emulation Verification

- **Date:** 2026-10-31
- **Tool:** LocalStack 4.4.0 community, Terraform AWS provider 5.x, AWS CLI
- **Result:** PASS — 22/22 assertions, 17 resources applied and destroyed
- **Evidence directory:** `docs/evidence/localstack/`

## What was executed

```bash
tests/localstack/run-localstack-tests.sh
```

The script:

1. Started/reused LocalStack at `http://localhost:4566`.
2. Initialized and applied `tests/localstack/terraform/`.
3. Verified resources through the AWS CLI.
4. Destroyed all fixture resources.

## Assertions

| Area | Checks |
| --- | --- |
| S3 | Bucket exists, versioning `Enabled`, AES256 encryption, all public-access blocks, object upload/download |
| DynamoDB | Table `ACTIVE`, `PAY_PER_REQUEST`, put/get item |
| SQS/SNS | Queue exists, topic exists, published SNS message received from SQS |
| KMS | Alias exists |
| CloudWatch Logs | Log group exists with 30-day retention |
| IAM | Runtime role exists |
| EC2 networking | VPC tagged `aegis-local-vpc` exists |

Artifacts: `run.log`, `assertions.log`, `terraform-apply.log`,
`terraform-destroy.log`, `terraform-output.json`, `result.json`.

## What this closes

It verifies that Terraform can authenticate against an AWS-compatible endpoint,
create and read back supported resources, and that the AWS CLI can observe them.
It also verifies an SNS→SQS integration path with an actual message.

## What it does not close

- No GovCloud, EKS, ECS, RDS/Aurora, or production module apply.
- No Azure or GCP execution.
- No live-account IAM, quota, networking, or provider 6.x validation.
- No proof of runtime control effectiveness.

The fixture intentionally uses AWS provider 5.x because LocalStack 4.4.0
community did not complete DynamoDB update waiters with provider 6.x. Production
remains on provider 6.x and still requires a sandbox/live-account run.

## Recommended next step

Use an authorized AWS GovCloud sandbox account for a plan/apply of the AWS
modules, then repeat for Azure Government and GCP. The LocalStack harness is a
fast pre-check, not a replacement for that authorization-boundary test.
