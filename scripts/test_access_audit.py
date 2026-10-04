"""Unit tests for the access audit allow-list (run: python -m unittest scripts/test_access_audit.py)."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from access_audit import violations  # noqa: E402

R, D = "runner-id", "deployer-id"


class AllowList(unittest.TestCase):
    def v(self, securable, name, grants):
        return violations(securable, name, {k: set(p) for k, p in grants.items()}, R, D)

    def test_intended_setup_passes(self):
        self.assertEqual(self.v("catalog", "finance", {"finance-analysts": ["USE_CATALOG"], R: ["USE_CATALOG"], D: ["USE_CATALOG"]}), [])
        self.assertEqual(self.v("schema", "finance.gold", {"finance-analysts": ["USE_SCHEMA", "SELECT"], R: ["SELECT", "MODIFY"]}), [])
        self.assertEqual(self.v("schema", "finance.ops", {D: ["USE_SCHEMA", "READ_VOLUME", "WRITE_VOLUME"]}), [])
        self.assertEqual(self.v("table", "finance.silver.pos_sales", {"finance-data-engineers": ["ALL_PRIVILEGES"]}), [])

    def test_analysts_below_gold_is_a_violation(self):
        self.assertEqual(len(self.v("table", "finance.silver.pos_sales", {"finance-analysts": ["SELECT"]})), 1)

    def test_broad_groups_and_catalog_wide_select(self):
        self.assertEqual(len(self.v("schema", "finance.bronze", {"account users": ["SELECT"]})), 1)
        self.assertEqual(len(self.v("catalog", "finance", {"finance-analysts": ["SELECT"]})), 1)

    def test_runner_must_not_manage_and_deployer_stays_in_ops(self):
        self.assertEqual(len(self.v("schema", "finance.silver", {R: ["MANAGE"]})), 1)
        self.assertEqual(len(self.v("schema", "finance.silver", {D: ["SELECT"]})), 1)
        self.assertEqual(len(self.v("schema", "finance.gold", {"finance-analysts": ["MODIFY"]})), 1)


if __name__ == "__main__":
    unittest.main()
