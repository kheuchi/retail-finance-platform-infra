# CI/CD

**Contents:** [TL;DR](#tldr) · [On every pull request](#on-every-pull-request) · [On merge to `main`](#on-merge-to-main) · [To deploy](#to-deploy) · [Why it's safe](#why-its-safe)

Diagram and roles: [LLD 2 · Identity & CI/CD](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/architecture/lld-identity-cicd.md).
How it was built: stories [1.2](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/1.2-passwordless-cicd.md) and [1.3](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/1.3-least-privilege-deploy-role.md).

## TL;DR

| Stage | What runs | Gate |
|---|---|---|
| Pull request | fmt, validate, shell check, Checkov | Required checks, admins included |
| Merge to `main` | Real plan of both stacks (read-only role), automatic release | — |
| Deploy | Plan, save, apply exactly that plan | Manual dispatch, type `apply` |

## On every pull request

> **TL;DR:** nothing merges unchecked. Detail: [`../cmdb.yml`](../cmdb.yml) → `ci_cd.branch_protection_main`

Format, validate both stacks, check shell scripts, scan with Checkov.
Merge needs a pull request, green `Terraform checks` and `Checkov`, and applies to admins too.

## On merge to `main`

> **TL;DR:** prove the plan against real AWS, then release. Detail: [`../cmdb.yml`](../cmdb.yml) → `ci_cd.workflows`

A real Terraform plan of both stacks against AWS (read-only role), then an automatic
release from the commit messages (`feat:` minor, `fix:` patch, `feat!:` major).

## To deploy

> **TL;DR:** a human types `apply`; the pipeline does the rest. Detail: [`../cmdb.yml`](../cmdb.yml) → `ci_cd.workflows`

**Actions → Deploy AWS Bootstrap** or **Deploy Databricks Workspace** → type `apply`.
The job plans, saves the plan, and applies exactly that file. Both workflows share a
lock group, so they never run at once. Wait for post-merge CI to finish first.

## Why it's safe

> **TL;DR:** no keys to steal, narrow roles, pinned actions. Detail: [`../cmdb.yml`](../cmdb.yml) → `iam`, `ci_cd`

| Control | Effect |
|---|---|
| OIDC, trusted by numeric repo ID | No AWS keys in GitHub; a renamed repo cannot inherit the trust |
| Plan role read-only, deploy role scoped per resource | A stolen token has limited reach |
| Actions pinned to commit SHAs, Dependabot | No surprise code in the pipeline |
| Secret scanning and push protection | Secrets cannot be pushed by mistake |

Honest limit: one maintainer, so required approvals are 0. The gate is the PR plus
the manual dispatch, not a second reviewer.

Settings, variables and secret names: `cmdb.yml` → `ci_cd`. Debug a run: `gh run view <id> --log-failed`.
