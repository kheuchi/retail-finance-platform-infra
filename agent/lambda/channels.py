"""Channel tools for the month-end agents, exposed as MCP tools by AgentCore Gateway (story 7.1).

The guardrails live here, outside the model (ADR-006):
- submit_draft: every number in a draft must match a figure returned by the agent's own
  tool functions for that month; otherwise the draft is stored as rejected_by_check.
- send_approved: sends only a draft that a controller approved in finance.agent.approvals,
  and only once. The agent cannot approve: it has no grant on that table.

Runs as finance-close-notifier through the Databricks SQL Statement API. Standard library
and boto3 only (the Lambda runtime provides both).
"""

from __future__ import annotations

import base64
import json
import os
import re
import time
import urllib.parse
import urllib.request
import uuid
from decimal import ROUND_HALF_UP, Decimal

HOST = os.environ["DATABRICKS_HOST"].rstrip("/")
WAREHOUSE = os.environ["WAREHOUSE_ID"]
SECRET_ARN = os.environ["NOTIFIER_SECRET_ARN"]
EMAIL = os.environ["CHANNEL_EMAIL"]
FUNCTIONS = [f.strip() for f in os.environ["AGENT_FUNCTIONS"].split(",") if f.strip()]
MONTH = re.compile(r"^\d{4}-(0[1-9]|1[0-2])$")
_token: dict = {}


# ── Databricks ────────────────────────────────────────────────────────
def token() -> str:
    if _token.get("exp", 0) > time.time() + 60:
        return _token["value"]
    import boto3  # provided by the Lambda runtime; imported here so tests run without it

    creds = json.loads(boto3.client("secretsmanager").get_secret_value(SecretId=SECRET_ARN)["SecretString"])
    body = urllib.parse.urlencode({"grant_type": "client_credentials", "scope": "all-apis"}).encode()
    req = urllib.request.Request(f"{HOST}/oidc/v1/token", data=body, method="POST")
    basic = f"{creds['client_id']}:{creds['client_secret']}".encode()
    req.add_header("Authorization", "Basic " + base64.b64encode(basic).decode())
    with urllib.request.urlopen(req, timeout=20) as r:
        t = json.load(r)
    _token.update(value=t["access_token"], exp=time.time() + int(t.get("expires_in", 3600)))
    return _token["value"]


def _call(method: str, path: str, payload: dict | None = None) -> dict:
    req = urllib.request.Request(f"{HOST}{path}", method=method, data=json.dumps(payload).encode() if payload else None)
    req.add_header("Authorization", f"Bearer {token()}")
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def sql(statement: str, **params) -> list[dict]:
    """Run one parameterised statement; return rows as dicts."""
    body = {
        "warehouse_id": WAREHOUSE,
        "statement": statement,
        "parameters": [{"name": k, "value": None if v is None else str(v), "type": "STRING"} for k, v in params.items()],
        "wait_timeout": "30s",
        "format": "JSON_ARRAY",
        "disposition": "INLINE",
    }
    r = _call("POST", "/api/2.0/sql/statements", body)
    deadline = time.time() + 90
    while r["status"]["state"] in ("PENDING", "RUNNING") and time.time() < deadline:
        time.sleep(2)
        r = _call("GET", f"/api/2.0/sql/statements/{r['statement_id']}")
    if r["status"]["state"] != "SUCCEEDED":
        raise RuntimeError(f"SQL failed: {r['status']}")
    cols = [c["name"] for c in r.get("manifest", {}).get("schema", {}).get("columns", [])]
    return [dict(zip(cols, row, strict=True)) for row in r.get("result", {}).get("data_array", []) or []]


# ── Figure check ──────────────────────────────────────────────────────
NUMBER = re.compile(
    r"(?<![\w.,])[-−]?(?:EUR\s?|€\s?)?(\d{1,3}(?:[, ]\d{3})+|\d+)(?:\.(\d+))?\s?(%|pts?|percentage points?|k\b|m\b|bn\b|million|thousand)?",
    re.IGNORECASE,
)
DATES = re.compile(r"\b\d{4}-\d{2}(?:-\d{2})?\b|\b(?:19|20)\d{2}\b")
SCALE = {"k": Decimal(1000), "thousand": Decimal(1000), "m": Decimal(10**6), "million": Decimal(10**6), "bn": Decimal(10**9)}


def tool_figures(month: str) -> list[Decimal]:
    out = []
    for fn in FUNCTIONS:
        for row in sql(f"SELECT * FROM {fn}(:m)", m=month):
            for v in row.values():
                try:
                    out.append(Decimal(str(v)))
                except (ArithmeticError, ValueError, TypeError):
                    continue
    return out


def numbers_in(text: str) -> list[tuple[str, Decimal, int, str]]:
    """(as written, value, decimals, unit) for every figure in a draft; dates and years are not figures."""
    found = []
    for m in NUMBER.finditer(DATES.sub(" ", text)):
        whole, frac, unit = m.group(1).replace(",", "").replace(" ", ""), m.group(2) or "", (m.group(3) or "").lower()
        value = Decimal(f"{whole}.{frac}" if frac else whole)
        if not frac and not unit and value < 100:
            continue  # counts and ranks ("4 journals", "#1") are not checked
        found.append((m.group(0).strip(), value, len(frac), unit))
    return found


def matches(value: Decimal, decimals: int, unit: str, figures: list[Decimal]) -> bool:
    q = Decimal(1).scaleb(-decimals)
    scale = SCALE.get(unit.split()[0] if unit else "", Decimal(1))
    for f in figures:
        for candidate in (abs(f), abs(f) * 100):  # ratios may be written as percentages
            shown = (candidate / scale).quantize(q, rounding=ROUND_HALF_UP)
            if abs(shown - value) <= q:  # one unit in the last place for rounding differences
                return True
    return False


def check(month: str, body: str) -> list[str]:
    figures = tool_figures(month)
    return [w for w, v, d, u in numbers_in(body) if not matches(v, d, u, figures)]


# ── Tools ─────────────────────────────────────────────────────────────
def submit_draft(month: str, audience: str, title: str, body: str) -> dict:
    if not MONTH.match(month or ""):
        return {"error": "month must be YYYY-MM"}
    unmatched = check(month, body)
    status = "rejected_by_check" if unmatched else "pending_review"
    draft_id = str(uuid.uuid4())
    sql(
        "INSERT INTO finance.agent.drafts (draft_id, month, audience, title, body, status, check_detail, created_at) "
        "VALUES (:id, :month, :audience, :title, :body, :status, :detail, current_timestamp())",
        id=draft_id, month=month, audience=audience[:40], title=title[:200], body=body[:20000], status=status,
        detail=json.dumps({"unmatched_figures": unmatched}),
    )
    return {"draft_id": draft_id, "status": status, "unmatched_figures": unmatched}


def list_drafts(month: str) -> dict:
    rows = sql(
        "SELECT d.draft_id, d.audience, d.title, d.status, d.sent_at, a.decision, a.approver "
        "FROM finance.agent.drafts d LEFT JOIN (SELECT * FROM finance.agent.approvals "
        "QUALIFY row_number() OVER (PARTITION BY draft_id ORDER BY decided_at DESC) = 1) a USING (draft_id) "
        "WHERE d.month = :m ORDER BY d.created_at",
        m=month,
    )
    return {"drafts": rows}


def send_approved(draft_id: str) -> dict:
    rows = sql(
        "SELECT d.month, d.title, d.body, d.status, d.sent_at, a.decision, a.approver "
        "FROM finance.agent.drafts d LEFT JOIN (SELECT * FROM finance.agent.approvals "
        "QUALIFY row_number() OVER (PARTITION BY draft_id ORDER BY decided_at DESC) = 1) a USING (draft_id) "
        "WHERE d.draft_id = :id",
        id=draft_id,
    )
    if not rows:
        return {"sent": False, "reason": "unknown draft"}
    d = rows[0]
    if d["decision"] != "approved":
        return {"sent": False, "reason": "not approved by a controller"}
    if d["sent_at"]:
        return {"sent": False, "reason": "already sent"}
    if d["status"] != "pending_review":
        return {"sent": False, "reason": f"status is {d['status']}"}
    import boto3

    boto3.client("sesv2").send_email(
        FromEmailAddress=EMAIL,
        Destination={"ToAddresses": [EMAIL]},
        Content={"Simple": {"Subject": {"Data": f"[Finance close {d['month']}] {d['title']}"},
                            "Body": {"Text": {"Data": f"{d['body']}\n\nApproved by {d['approver']}. Draft {draft_id}."}}}},
    )
    sql(
        "INSERT INTO finance.gold.close_commentary (month, title, body, draft_id, approved_by, published_at) "
        "VALUES (:month, :title, :body, :id, :approver, current_timestamp())",
        month=d["month"], title=d["title"], body=d["body"], id=draft_id, approver=d["approver"],
    )
    sql("UPDATE finance.agent.drafts SET status = 'sent', sent_at = current_timestamp(), channel = 'email' WHERE draft_id = :id",
        id=draft_id)
    return {"sent": True, "channel": "email", "published": "finance.gold.close_commentary"}


TOOLS = {"submit_draft": submit_draft, "list_drafts": list_drafts, "send_approved": send_approved}


def handler(event, context):
    name = (context.client_context.custom or {}).get("bedrockAgentCoreToolName", "")
    tool = name.split("___")[-1]
    if tool not in TOOLS:
        return {"error": f"unknown tool {name}"}
    try:
        return TOOLS[tool](**event)
    except TypeError as e:
        return {"error": f"bad arguments: {e}"}
