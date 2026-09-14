# Terraform Bootstrap

This stack establishes the minimum safe foundation needed by later Terraform
stacks:

- private, encrypted and versioned S3 storage for Terraform state;
- a monthly USD 50 AWS Budget, with optional 50%, 80% and forecasted-100% alerts;
- an account password policy for IAM users.

Plain words: this stack creates the locked filing cabinet for infrastructure records
and the spending alarm before the platform is deployed.

## Safety properties

- It does not create compute, databases, NAT Gateways or Databricks resources.
- The state bucket has `prevent_destroy` and cannot be removed accidentally by a
  normal Terraform destroy.
- It uses S3-managed AES-256 encryption to avoid a persistent customer-managed KMS
  key charge at this bootstrap stage.
- It creates no IAM access keys and contains no credentials.
- The initial bootstrap state is local and must be protected until it is migrated.

## Prepare—but do not apply without review

```bash
export AWS_PROFILE=retail-platform-admin
./scripts/plan-bootstrap.sh
```

The planning script attempts to read a registered AWS contact email at runtime.
AWS does not expose the root email for a standalone account through this API, so the
budget is created without notifications unless a valid local variable is supplied.
Copy `bootstrap/terraform.tfvars.example` to `bootstrap/terraform.tfvars` to enable
alerts. That local file is ignored by Git.

An explicit approval is required before:

```bash
./scripts/apply-bootstrap.sh
```

After the state bucket exists, later stacks will use the S3 backend with native
`use_lockfile = true`. DynamoDB locking is intentionally omitted because it is
deprecated for the S3 backend.

The bootstrap stack also migrates its own state to the protected bucket under
`bootstrap/terraform.tfstate`. Backend settings are supplied during initialization
and credentials are never embedded in Terraform files.

Run the repository helper after the first bootstrap apply:

```bash
export AWS_PROFILE=retail-platform-admin
./scripts/init-backend.sh
```

Terraform 1.14 does not directly recognize AWS CLI `login_session` credentials in
the S3 backend. The helper converts the existing short-lived session to environment
variables for the Terraform process and removes them when it exits. It never creates
or stores long-lived access keys.
