"""Store guarantees, stdlib-only so they run anywhere (python3 test_store.py)."""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from models.store import (
    get_reasoning,
    get_vault,
    init_db,
    last_rebalance,
    list_vaults,
    record_rebalance,
    store_reasoning,
    upsert_vault,
)


class StoreTest(unittest.TestCase):
    def setUp(self):
        self.path = os.path.join(tempfile.mkdtemp(), "t.db")
        init_db(self.path)
        upsert_vault(self.path, "0xABC", "AI Mega Cap", "vAI", ["0x1"], [10_000], 1)

    def test_vault_round_trip_case_insensitive(self):
        self.assertIsNotNone(get_vault(self.path, "0xabc"))
        self.assertIsNone(get_vault(self.path, "0x0"))

    def test_pagination(self):
        upsert_vault(self.path, "0xDEF", "E", "vE", ["0x2"], [10_000], 2)
        self.assertEqual(len(list_vaults(self.path, 1, 0)), 1)
        self.assertEqual(len(list_vaults(self.path, 10, 5)), 0)

    def test_reasoning_tamper_evidence(self):
        doc = '{"vault":"0xabc","nonce":0}'
        self.assertEqual(store_reasoning(self.path, "0xabc", 0, 1, doc, "0x"), "inserted")
        self.assertEqual(store_reasoning(self.path, "0xabc", 0, 1, doc, "0x"), "identical")
        self.assertEqual(
            store_reasoning(self.path, "0xabc", 0, 1, '{"vault":"0xabc","nonce":1}', "0x"),
            "conflict",
        )
        self.assertIsNotNone(get_reasoning(self.path, "0xabc", 0))
        self.assertIsNone(get_reasoning(self.path, "0xabc", 9))

    def test_rebalance_log_newest_first(self):
        self.assertIsNone(last_rebalance(self.path))
        record_rebalance(self.path, "0xabc", 0, "0x1", 100)
        record_rebalance(self.path, "0xabc", 1, "0x2", 200)
        last = last_rebalance(self.path)
        self.assertEqual((last["nonce"], last["created_at"]), (1, 200))


if __name__ == "__main__":
    unittest.main(verbosity=1)
