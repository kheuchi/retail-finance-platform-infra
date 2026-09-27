# AGENTS.md

Instructions for any AI assistant working in this repo. Tool-neutral; `CLAUDE.md` imports this file.

| Question | Answer |
|---|---|
| Project rules, way of working, how to report | **Read first:** [control-plane AGENTS.md](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/AGENTS.md) |
| This repo | Terraform for the AWS foundation, private network and Databricks workspace ([README](README.md)) |
| Changes | Pull request only; `Terraform checks` and `Checkov` must pass; deploy via **Actions → Deploy …** (type `apply`), never from a laptop |
| IAM changes | Two-phase: grant in one apply, use in the next; run the IAM policy simulator first |
| Before any AWS command | Check the account (`aws sts get-caller-identity`); never root; region `eu-central-1` |
| Facts and incidents | [`cmdb.yml`](cmdb.yml); explanations in the [stories](https://github.com/kheuchi/retail-finance-platform-control-plane/blob/main/docs/stories/README.md) |
