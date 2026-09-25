# CI/CD

**Contents:** [On every pull request](#on-every-pull-request) · [On merge to `main`](#on-merge-to-main) · [To deploy](#to-deploy) · [Why it's safe](#why-its-safe)

## On every pull request

> Detail: [`../cmdb.yml`](../cmdb.yml) → `ci_cd.branch_protection_main`

Format, validate both stacks, check shell scripts, scan with Checkov.
Merge needs a pull request, green `Terraform checks` and `Checkov`, and applies to admins too.

## On merge to `main`

> Detail: [`../cmdb.yml`](../cmdb.yml) → `ci_cd.workflows`

A real Terraform plan of both stacks against AWS (read-only role), then an automatic
release from the commit messages (`feat:` minor, `fix:` patch, `feat!:` major).

## To deploy

> Detail: [`../cmdb.yml`](../cmdb.yml) → `ci_cd.workflows`

**Actions → Deploy AWS Bootstrap** or **Deploy Databricks Workspace** → type `apply`.
The job plans, saves the plan, and applies exactly that file. Both workflows share a
lock group, so they never run at once. Wait for post-merge CI to finish first.

## Why it's safe

> Detail: [`../cmdb.yml`](../cmdb.yml) → `iam, ci_cd`

- No AWS keys in GitHub: short-lived OIDC sessions, trusted by numeric repo ID.
- Plan role is read-only; deploy role is scoped per resource.
- Actions pinned to commit SHAs; Dependabot keeps them current.
- Secret scanning and push protection on (the repo is public).

Honest limit: one maintainer, so required approvals are 0. The gate is the PR plus
the manual dispatch, not a second reviewer.

Settings, variables and secret names: `cmdb.yml` → `ci_cd`.
Debug a run: `gh run view <id> --log-failed`.
