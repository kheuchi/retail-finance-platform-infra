# Single-Account Landing-Zone Design

## Decision summary

The project will preserve the AWS Free plan by not creating AWS Organizations or
Control Tower. It will deploy an enterprise-inspired baseline inside one account and
document the multi-account target separately.

Plain words: one AWS account will contain carefully separated areas instead of using
separate accounts as hard walls. This is less isolated than production, but it lets
us practise the same policies and automation within the available budget.

Technical consequence: IAM roles, resource policies, KMS keys, tags, naming and
Terraform state boundaries provide logical isolation. They do not provide the same
blast-radius boundary as separate AWS accounts and SCPs.

## Regions

- Management/bootstrap, workload and AI region: `eu-central-1` (Frankfurt).
- Frankfurt keeps processing in the EU and currently supports Databricks custom
  CPU/GPU model serving, agent serving, external models, Foundation Model APIs, and
  Amazon Bedrock Custom Model Import. Stockholm and Paris do not provide the
  required Databricks custom model-serving capability.
- Keeping regional resources together reduces operational complexity, cross-region
  transfer paths, and the number of residency boundaries to explain and govern.
- Global services such as IAM, CloudFront and AWS Budgets are managed deliberately
  rather than assumed to be regional.

## Logical environments

| Boundary | Plain meaning | Technical enforcement |
|---|---|---|
| `shared` | Common security and delivery services | Dedicated Terraform state, IAM roles, KMS keys and tags |
| `dev` | Fast experimentation with bounded access | Developer role, budget limits, short retention and small compute |
| `stage` | Production-like validation | CI-only deployments and production-equivalent tests |
| `prod` | Demonstration of controlled releases | Approval gate, restricted role and protected data products |

Not all three environments must run concurrently. Stage and production resources
should be ephemeral where possible.

## Identity model

- Root user: MFA-protected emergency/bootstrap identity only.
- `cheikh-platform-admin`: named bootstrap administrator using browser-based
  `aws login` temporary credentials; no access keys.
- Future human roles: platform administrator, security auditor, data engineer, data
  scientist, finance analyst and finance data owner.
- CI/CD role: trusted only from an approved GitHub repository and branch/environment
  through OIDC; no stored AWS secret keys.
- Workload roles: separate ingestion, transformation, ML and agent roles with
  least-privilege policies.

The bootstrap administrator will remain broad initially. Routine operations will
move to assumable roles as the baseline is created.

## Foundation controls

### Cost protection

- Monthly AWS budget target: USD 50.
- Alerts at forecast/actual thresholds before the ceiling.
- Mandatory cost allocation tags.
- No NAT Gateway in the first deployment; it has an hourly cost even when idle.
- No always-on EC2, RDS, streaming clusters or Databricks classic clusters.
- Short log retention where compatible with the learning objective.

### Audit and detection

- Multi-region CloudTrail management-event trail to an encrypted S3 bucket.
- S3 access restrictions, versioning and lifecycle rules for audit evidence.
- CloudWatch alarms for selected high-risk activity where affordable.
- AWS Config scoped carefully because configuration-item recording is usage-priced.
- GuardDuty and Security Hub remain documented controls while the Free plan reports
  them as unavailable; this exception must be visible in the control matrix.

### Data protection

- Separate KMS keys by security purpose where justified.
- S3 Block Public Access at account and bucket levels.
- TLS-only bucket policies.
- Data classification tags: `public`, `internal`, `confidential`, `restricted`.
- No real payment-card data or customer PII; sensitive columns are synthetic.

### Network

- Do not use the default VPC for platform workloads.
- Create a dedicated VPC only if required by the selected Databricks deployment.
- Prefer serverless services to avoid persistent NAT and compute costs.
- Restrict outbound connectivity and public ingress.

## What is intentionally not equivalent to enterprise production

- Logical environment boundaries are weaker than AWS account boundaries.
- There are no organization-level SCPs or centralized delegated administrators.
- Audit logs are stored in the same account as workloads.
- A sufficiently privileged account administrator can alter all controls.

These are accepted portfolio constraints, not hidden gaps. The reference
multi-account design will show how Control Tower corrects them.

## Deployment gates

Before the first Terraform apply:

1. Named non-root identity and MFA verified.
2. Management and workload region explicitly set to `eu-central-1`.
3. Cost estimate and budget notification address agreed.
4. Terraform plan reviewed for persistent hourly resources.
5. Destruction and recovery behavior documented.
6. No secrets or account-specific credentials tracked by Git.
