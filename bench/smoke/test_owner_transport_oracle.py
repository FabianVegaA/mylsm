import unittest
from owner_transport_oracle import Oracle


class TransportOracleTests(unittest.TestCase):
    def run_records(self, records):
        oracle = Oracle()
        for record in records:
            oracle.accept("MYLSM_TRANSPORT " + record)
        return oracle

    def test_reservation_transfer_and_release_conserve_credit(self):
        oracle = self.run_records([
            "open 1 2 284", "reserve 1 25 284 128", "frame 1 284 156",
            "census 1 284 156 28 24", "close 1", "census 0 0 0 0 0",
        ])
        self.assertEqual((oracle.acquired, oracle.released, oracle.peak),
                         (284, 284, 284))

    def test_detects_broken_ownership_and_budget_records(self):
        cases = [
            ["open 1 1 284", "open 2 1 284"],
            ["open 1 2 283", "reserve 1 25 284 128"],
            ["open 1 2 284", "reserve 1 25 284 128", "reserve 1 25 284 128"],
            ["open 1 2 284", "reserve 1 25 284 128", "frame 1 282 156"],
            ["open 1 2 284", "reserve 1 25 284 128", "frame 1 284 157"],
            ["open 1 2 284", "close 1", "close 1"],
            ["open 1 2 284", "census 1 0 0 0 24"],
            ["open 1 2 284", "reserve 1 25 284 128", "census 1 0 156 28 24"],
        ]
        for records in cases:
            with self.subTest(records=records), self.assertRaises(AssertionError):
                self.run_records(records)

    def test_control_response_uses_only_its_separate_slot(self):
        oracle = self.run_records([
            "open 1 1 28", "frame 1 0 28", "census 1 0 28 28 24",
            "close 1", "census 0 0 0 0 0",
        ])
        self.assertEqual(oracle.acquired, 0)
        self.assertEqual(oracle.slot_peak, 52)


if __name__ == "__main__":
    unittest.main()
