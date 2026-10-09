"""Rate-limit tiers + address gate. Runs on stdlib + fastapi (no web3 needed)."""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from fastapi import HTTPException

from core.security import READ_LIMIT, WRITE_LIMIT, check_rate_limit, checksum


class RateLimitTest(unittest.TestCase):
    def test_read_budget_429_with_retry_after(self):
        ip = "tier-read"
        for _ in range(READ_LIMIT):
            check_rate_limit(ip, READ_LIMIT)
        with self.assertRaises(HTTPException) as ctx:
            check_rate_limit(ip, READ_LIMIT)
        self.assertEqual(ctx.exception.status_code, 429)
        self.assertIn("Retry-After", ctx.exception.headers)

    def test_write_budget_tighter_than_read(self):
        self.assertLess(WRITE_LIMIT, READ_LIMIT)
        ip = "tier-write"
        for _ in range(WRITE_LIMIT):
            check_rate_limit(ip, WRITE_LIMIT)
        with self.assertRaises(HTTPException) as ctx:
            check_rate_limit(ip, WRITE_LIMIT)
        self.assertEqual(ctx.exception.status_code, 429)

    def test_buckets_isolated_per_tier(self):
        # why: hammering reads must not spend the write budget (panel polling vs agent POSTs).
        ip = "tier-split"
        for _ in range(READ_LIMIT):
            check_rate_limit(ip, READ_LIMIT)
        check_rate_limit(ip, WRITE_LIMIT)  # must not raise


class ChecksumTest(unittest.TestCase):
    def test_shape_valid_passes_without_web3(self):
        self.assertEqual(checksum("0x" + "AB" * 20), "0x" + "ab" * 20)

    def test_garbage_rejected_400(self):
        for bad in ["not-an-address", "0x123", "", "0x" + "ZZ" * 20]:
            with self.assertRaises(HTTPException) as ctx:
                checksum(bad)
            self.assertEqual(ctx.exception.status_code, 400)


if __name__ == "__main__":
    unittest.main(verbosity=1)
