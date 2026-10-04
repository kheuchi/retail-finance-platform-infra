"""Figure check of the channel tools (run: python -m unittest agent/lambda/test_channels.py)."""

import os
import sys
import unittest
from decimal import Decimal
from pathlib import Path

for k in ("DATABRICKS_HOST", "WAREHOUSE_ID", "NOTIFIER_SECRET_ARN", "CHANNEL_EMAIL", "AGENT_FUNCTIONS"):
    os.environ.setdefault(k, "x")
sys.path.insert(0, str(Path(__file__).parent))
import channels  # noqa: E402

FIG = [Decimal("3431234.56"), Decimal("0.3431"), Decimal("-8166.73"), Decimal("12.4")]


class FigureCheck(unittest.TestCase):
    def ok(self, text):
        return [w for w, v, d, u in channels.numbers_in(text) if not channels.matches(v, d, u, FIG)]

    def test_figures_in_any_usual_form_pass(self):
        self.assertEqual(self.ok("Net sales EUR 3.43m (34.31% margin); journal of EUR 8,166.73; growth 12.4%."), [])
        self.assertEqual(self.ok("Sales reached 3,431,235 EUR."), [])

    def test_invented_figures_are_caught(self):
        # the review's probe: all of these passed the first version
        for claim in ("EUR 3.9m", "EUR 3.5m", "EUR 3.3m", "EUR 3m", "EUR 4m", "EUR 343m", "35%", "EUR 85", "EUR 2050", "EUR 3,9m"):
            self.assertEqual(len(self.ok(f"Net sales were {claim} this month.")), 1, claim)

    def test_legitimate_rounding_passes(self):
        self.assertEqual(self.ok("Margin 34 percent, growth 12 points, sales EUR 3.4m (truncated)."), [])

    def test_dates_years_counts_and_ids_are_ignored(self):
        self.assertEqual(self.ok("In August 2026 (2026-08-14) store S031 ranked #1; 4 journals; J20260811-S039-MAN4."), [])


if __name__ == "__main__":
    unittest.main()
