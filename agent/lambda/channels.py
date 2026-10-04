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
from decimal import ROUND_DOWN, ROUND_HALF_UP, Decimal

HOST = os.environ["DATABRICKS_HOST"].rstrip("/")
WAREHOUSE = os.environ["WAREHOUSE_ID"]
SECRET_ARN = os.environ["NOTIFIER_SECRET_ARN"]
EMAIL = os.environ["CHANNEL_EMAIL"]
FUNCTIONS = [f.strip() for f in os.environ["AGENT_FUNCTIONS"].split(",") if f.strip()]
MONTH = re.compile(r"^\d{4}-(0[1-9]|1[0-2])$")
AUDIENCES = {"cfo", "store_controlling", "gl_team"}
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
# A figure in a draft passes only if it equals a value returned by the agent's tool
# functions, rounded (half-up or truncated) at the precision written, in its unit. No
# tolerance beyond that. Percentages compare with values already in percent and with ratios
# x 100; plain numbers never get the x 100. Figures with fewer than two significant digits
# ("EUR 3m") cannot be verified and fail. Bare integers below 100 without a currency or unit
# are counts and ranks ("4 journals", "#1") and are not checked; standalone years and ISO
# dates are not figures. Signs are not compared: "down 2.3%" and "-2.3%" are both natural.
NUMBER = re.compile(
    r"(?<![\w.,])(?P<cur>EUR\s?|€\s?)?[-−+]?"
    r"(?P<int>\d{1,3}(?:[,\u202f]\d{3})+|\d+)"
    r"(?:(?P<dec_sep>[.,])(?P<frac>\d+))?"
    r"\s?(?P<unit>%|percent\b|pct\b|percentage points?\b|points?\b|pts?\b|bps\b|k\b|thousand\b|m\b|million\b|bn\b|billion\b)?",
    re.IGNORECASE,
)
ISO_DATE = re.compile(r"\b\d{4}-\d{2}(?:-\d{2})?\b")
SCALE = {"k": 3, "thousand": 3, "m": 6, "million": 6, "bn": 9, "billion": 9}
PERCENT = {"%", "percent", "pct", "percentage", "point", "points", "pt", "pts"}


def _unit(raw: str | None) -> str:
    return (raw or "").lower().split()[0] if raw else ""


def numbers_in(text: str) -> list[tuple[str, Decimal, int, str]]:
    """(as written, value, decimals, unit) for every figure in a draft."""
    found = []
    for m in NUMBER.finditer(ISO_DATE.sub(" ", text)):
        cur, unit = m.group("cur"), _unit(m.group("unit"))
        whole, frac, sep = m.group("int"), m.group("frac") or "", m.group("dec_sep")
        if sep == "," and not (len(frac) <= 2 and unit in SCALE):
            whole, frac = whole + frac, ""  # a thousands comma, not a decimal comma ("3,9m" is decimal)
        whole = whole.replace(",", "").replace("\u202f", "")
        value = Decimal(f"{whole}.{frac}" if frac else whole)
        if not frac and not unit and not cur:
            if value < 100 or (1990 <= value <= 2035 and len(whole) == 4):
                continue  # counts, ranks and years
        found.append((m.group(0).strip(), value, len(frac), unit))
    return found


def significant_digits(value: Decimal) -> int:
    return len(str(value).replace(".", "").replace("-", "").lstrip("0"))


def matches(value: Decimal, decimals: int, unit: str, figures: list[Decimal]) -> bool:
    if unit == "bps":
        value, decimals, unit = value / 100, decimals + 2, "%"
    if significant_digits(value) < 2:
        return False
    q = Decimal(1).scaleb(-decimals)
    shift = SCALE.get(unit, 0)
    candidates = []
    for f in figures:
        f = abs(f)
        candidates += [f, f * 100] if unit in PERCENT else [f.scaleb(-shift)]
    for c in candidates:
        for mode in (ROUND_HALF_UP, ROUND_DOWN):
            if c.quantize(q, rounding=mode) == value:
                return True
    return False


def tool_figures(month: str) -> tuple[list[Decimal], list[str]]:
    """Every numeric value the agent's tools return for the month, and the tools that failed."""
    out, failed = [], []
    for fn in FUNCTIONS:
        try:
            rows = sql(f"SELECT * FROM {fn}(:m)", m=month)
        except Exception as e:  # noqa: BLE001 - one failing tool must not hide the others
            failed.append(f"{fn}: {e}"[:300])
            continue
        for row in rows:
            for v in row.values():
                try:
                    out.append(Decimal(str(v)))
                except (ArithmeticError, ValueError, TypeError):
                    continue
    return out, failed


def check(month: str, text: str) -> tuple[list[str], list[str]]:
    figures, failed = tool_figures(month)
    if not figures:
        raise RuntimeError(f"no tool returned figures for {month}: {failed}")
    return [w for w, v, d, u in numbers_in(text) if not matches(v, d, u, figures)], failed


# ── Tools ─────────────────────────────────────────────────────────────
def submit_draft(month: str, audience: str, title: str, body: str) -> dict:
    if not MONTH.match(month or ""):
        return {"error": "month must be YYYY-MM"}
    if audience not in AUDIENCES:
        return {"error": f"audience must be one of {sorted(AUDIENCES)}"}
    unmatched, failed = check(month, f"{title}\n{body}")
    status = "rejected_by_check" if unmatched else "pending_review"
    draft_id = str(uuid.uuid4())
    sql(
        "INSERT INTO finance.agent.drafts (draft_id, month, audience, title, body, status, check_detail, created_at) "
        "VALUES (:id, :month, :audience, :title, :body, :status, :detail, current_timestamp())",
        id=draft_id, month=month, audience=audience, title=title[:200], body=body[:20000], status=status,
        detail=json.dumps({"unmatched_figures": unmatched, "tools_failed": failed}),
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
    # Claim the draft first: only one caller can move it out of pending_review.
    claimed = sql(
        "UPDATE finance.agent.drafts SET status = 'sending' "
        "WHERE draft_id = :id AND status = 'pending_review' AND sent_at IS NULL",
        id=draft_id,
    )
    if not claimed or int(claimed[0].get("num_affected_rows") or 0) != 1:
        return {"sent": False, "reason": f"not sendable (status {d['status']}, sent_at {d['sent_at']})"}
    import boto3

    try:
        boto3.client("sesv2").send_email(
            FromEmailAddress=EMAIL,
            Destination={"ToAddresses": [EMAIL]},
            Content={"Simple": {"Subject": {"Data": f"[Finance close {d['month']}] {d['title']}"},
                                "Body": {"Text": {"Data": f"{d['body']}\n\nApproved by {d['approver']}. Draft {draft_id}."}}}},
        )
    except Exception:
        sql("UPDATE finance.agent.drafts SET status = 'pending_review' WHERE draft_id = :id AND status = 'sending'",
            id=draft_id)
        raise
    sql("UPDATE finance.agent.drafts SET status = 'sent', sent_at = current_timestamp(), channel = 'email' WHERE draft_id = :id",
        id=draft_id)
    sql(
        "INSERT INTO finance.gold.close_commentary (month, title, body, draft_id, approved_by, published_at) "
        "VALUES (:month, :title, :body, :id, :approver, current_timestamp())",
        month=d["month"], title=d["title"], body=d["body"], id=draft_id, approver=d["approver"],
    )
    return {"sent": True, "channel": "email", "published": "finance.gold.close_commentary"}


TOOLS = {"submit_draft": submit_draft, "list_drafts": list_drafts, "send_approved": send_approved}


def handler(event, context):
    custom = getattr(getattr(context, "client_context", None), "custom", None) or {}
    name = custom.get("bedrockAgentCoreToolName", "")
    tool = name.split("___")[-1]
    if tool not in TOOLS:
        return {"error": f"unknown tool {name!r}"}
    if not isinstance(event, dict):
        return {"error": "arguments must be an object"}
    allowed = TOOLS[tool].__code__.co_varnames[: TOOLS[tool].__code__.co_argcount]
    unknown = set(event) - set(allowed)
    if unknown:
        return {"error": f"unknown arguments {sorted(unknown)}"}
    return TOOLS[tool](**event)
