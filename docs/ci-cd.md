# Infrastructure CI/CD

## Plain-language behavior

Every pull request checks that Terraform is formatted and valid. Checkov reports
security issues as advice while the baseline matures. A successful merge to `main`
uses commit messages to calculate a version and create a GitHub release.

## Technical flow

1. Terraform formatting and schema validation run without AWS credentials.
2. Repository shell scripts receive syntax validation with `bash -n`.
3. Checkov 3.3.17 scans Terraform; `continue-on-error` makes it non-blocking by
   explicit project decision.
4. semantic-release 25.0.9 runs on Node 24.15.0 only after Terraform checks succeed
   on `main`, creating a version tag and GitHub Release without pushing generated
   commits back into the protected branch.

## Conventional Commits

- `feat: ...` produces a minor release.
- `fix: ...` produces a patch release.
- `feat!: ...` or a `BREAKING CHANGE:` footer produces a major release.
- Other commit types normally produce no release.

## Security controls

- Workflow permissions default to read-only.
- Only the release job receives write permission.
- Actions are pinned to immutable commit SHAs.
- npm dependencies are exact and locked.
- Dependabot proposes controlled Actions and npm updates.
- CI uses no administrator profile or long-lived AWS keys.

## Required GitHub settings

- Default branch: `main`.
- Allow GitHub Actions to create repository releases.
- Protect `main` and require `Terraform checks` before merge.
- Do not require `Checkov advisory scan` while it remains non-blocking.

Run `./scripts/validate-local.sh` before committing to validate JSON, workflow YAML,
Terraform formatting, and shell syntax.
