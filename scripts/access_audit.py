"""Access audit for the finance catalog (story 4.5). Runs in CI as terraform-platform.

Only an owner or an admin can see every grant, so this check belongs to the platform, not to
the pipeline: the job identity (finance-pipeline-runner) cannot read other principals' grants,
and should not be able to. Terraform's grants are authoritative for the catalog and schemas;
this audit also covers what Terraform does not manage: every table and volume below Gold.

Allow-list:
- finance-analysts: USE_CATALOG/BROWSE on the catalog; USE_SCHEMA + SELECT on gold (and gold
  tables); nothing below Gold.
- account users / users: nothing but BROWSE anywhere.
- finance-pipeline-runner: never MANAGE or ALL_PRIVILEGES (it must not administer access).
- finance-data-deployer: USE_CATALOG; USE_SCHEMA, READ_VOLUME, WRITE_VOLUME on ops; nothing else.

Exit code 1 on any violation. Standard library only (no install in CI).
Env: DATABRICKS_HOST, DATABRICKS_CLIENT_ID, DATABRICKS_CLIENT_SECRET, RUNNER_ID, DEPLOYER_ID.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.parse
import urllib.request

CATALOG = "finance"
BELOW_GOLD = ("raw", "bronze", "silver", "ops", "ml", "agent")
ANALYSTS, BROAD = "finance-analysts", ("account users", "users")
CONTROLLERS = "finance-controllers"
AGENT_GOLD_TABLES = {"daily_revenue", "budget_variance", "margin", "margin_alerts", "recon_exceptions", "revenue_forecast"}


def agent_platform_allowed(kind: str, securable: str, name: str) -> set[str]:
    """What the agent platform's principals may hold (story 7.1). ``kind`` is agent, notifier or controllers."""
    parts = name.split(".")
    schema = parts[1] if len(parts) > 1 else None
    table = parts[2] if len(parts) > 2 else None
    if securable == "catalog":
        return {"USE_CATALOG"}
    if securable == "schema":
        if schema == "agent":
            return {"USE_SCHEMA"} if kind == "controllers" else {"USE_SCHEMA", "EXECUTE"}
        return {"USE_SCHEMA"} if schema == "gold" and kind != "controllers" else set()
    if securable == "table":
        if schema == "gold" and table in AGENT_GOLD_TABLES and kind != "controllers":
            return {"SELECT"}
        if kind == "notifier":
            return {"agent.drafts": {"SELECT", "MODIFY"}, "agent.approvals": {"SELECT"}, "gold.close_commentary": {"SELECT", "MODIFY"}}.get(f"{schema}.{table}", set())
        if kind == "controllers":
            return {"agent.drafts": {"SELECT"}, "agent.approvals": {"SELECT", "MODIFY"}}.get(f"{schema}.{table}", set())
    return set()


def violations(securable: str, name: str, grants: dict[str, set[str]], runner: str, deployer: str, agent: str = "", notifier: str = "") -> list[str]:
    """Pure allow-list check for one securable. ``securable`` is catalog, schema, table or volume."""
    schema = name.split(".")[1] if name.count(".") >= 1 else None
    out = []
    for principal, privs in grants.items():
        if principal == ANALYSTS:
            if securable == "catalog":
                allowed = {"USE_CATALOG", "BROWSE"}
            elif schema == "gold":
                allowed = {"USE_SCHEMA", "SELECT"}
            else:
                allowed = set()
        elif principal in BROAD:
            allowed = {"BROWSE"}
        elif principal == deployer:
            allowed = {"USE_CATALOG"} if securable == "catalog" else set()
            if schema == "ops" and securable in ("schema", "volume"):
                allowed = {"USE_SCHEMA", "READ_VOLUME", "WRITE_VOLUME"}
        elif principal in {agent, notifier, CONTROLLERS} - {""}:
            kind = "agent" if principal == agent else "notifier" if principal == notifier else "controllers"
            allowed = agent_platform_allowed(kind, securable, name)
        elif principal == runner:
            extra = privs & {"MANAGE", "ALL_PRIVILEGES"}
            if extra:
                out.append(f"{principal} has {sorted(extra)} on {securable} {name}")
            continue
        else:
            continue  # engineers and admins are governed by Terraform, not by this allow-list
        extra = privs - allowed
        if extra:
            out.append(f"{principal} has {sorted(extra)} on {securable} {name}")
    return out


class Client:
    def __init__(self, host: str, client_id: str, secret: str):
        self.host = host.rstrip("/")
        body = urllib.parse.urlencode({"grant_type": "client_credentials", "scope": "all-apis"}).encode()
        req = urllib.request.Request(f"{self.host}/oidc/v1/token", data=body, method="POST")
        import base64

        req.add_header("Authorization", "Basic " + base64.b64encode(f"{client_id}:{secret}".encode()).decode())
        with urllib.request.urlopen(req, timeout=30) as r:
            self.token = json.load(r)["access_token"]

    def get(self, path: str, **query) -> dict:
        url = f"{self.host}{path}" + (f"?{urllib.parse.urlencode(query)}" if query else "")
        req = urllib.request.Request(url, headers={"Authorization": f"Bearer {self.token}"})
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r)

    def grants(self, securable: str, name: str) -> dict[str, set[str]]:
        d = self.get(f"/api/2.1/unity-catalog/permissions/{securable}/{urllib.parse.quote(name)}")
        return {a["principal"]: set(a.get("privileges", [])) for a in d.get("privilege_assignments", [])}


def main() -> int:
    env = os.environ
    c = Client(env["DATABRICKS_HOST"], env["DATABRICKS_CLIENT_ID"], env["DATABRICKS_CLIENT_SECRET"])
    runner, deployer = env["RUNNER_ID"], env["DEPLOYER_ID"]
    agent, notifier = env.get("AGENT_ID", ""), env.get("NOTIFIER_ID", "")

    found, checked = [], 0
    targets = [("catalog", CATALOG)] + [("schema", f"{CATALOG}.{s}") for s in (*BELOW_GOLD, "gold")]
    for s in (*BELOW_GOLD, "gold"):
        targets += [("table", t["full_name"]) for t in c.get("/api/2.1/unity-catalog/tables", catalog_name=CATALOG, schema_name=s).get("tables", [])]
        targets += [("volume", v["full_name"]) for v in c.get("/api/2.1/unity-catalog/volumes", catalog_name=CATALOG, schema_name=s).get("volumes", [])]
    for securable, name in targets:
        found += violations(securable, name, c.grants(securable, name), runner, deployer, agent, notifier)
        checked += 1

    print(f"access audit: {checked} securables checked, {len(found)} violation(s)")
    for v in found:
        print("  VIOLATION", v)
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
