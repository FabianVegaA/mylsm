import json
import sys
import time
from pathlib import Path


class Oracle:
    def __init__(self):
        self.connections = {}
        self.seen = set()
        self.acquired = 0
        self.released = 0
        self.peak = 0
        self.slot_peak = 0
        self.censuses = 0

    def reserved(self):
        return sum(item[0] for item in self.connections.values())

    def accept(self, line):
        if not line.startswith("MYLSM_TRANSPORT "):
            return
        _, event, *fields = line.split()
        values = list(map(int, fields))
        if event == "open":
            identifier, maximum, capacity = values
            assert identifier not in self.seen, "connection identifier reused"
            self.seen.add(identifier)
            self.connections[identifier] = [0, None, False, capacity]
            assert len(self.connections) <= maximum, "control/header slots exceeded"
            self.slot_peak = max(self.slot_peak, 52 * len(self.connections))
        elif event == "reserve":
            identifier, request_bytes, peak, limit = values
            current = self.connections[identifier]
            assert current[1] is None, "request dispatched more than once"
            assert request_bytes >= 24, "request lost its encoded size"
            assert peak == 2 * limit + 28, "TX peak omitted encoding overlap"
            current[0], current[1] = peak, limit
            self.acquired += peak
            assert self.reserved() <= current[3], "TX reservations exceeded capacity"
            self.peak = max(self.peak, self.reserved())
        elif event == "frame":
            identifier, peak, length = values
            current = self.connections[identifier]
            assert not current[2], "reservation transferred twice"
            assert peak == current[0], "frame changed the dispatch reservation"
            if current[1] is None:
                assert peak == 0 and length == 28, "unreserved data response"
            else:
                assert 28 <= length <= current[1] + 28, "frame exceeded its preflight bound"
                assert 2 * (length - 28) + 28 <= peak, "encoding peak exceeded reservation"
            current[2] = True
        elif event == "close":
            identifier, = values
            assert identifier in self.connections, "connection released twice or without admission"
            peak, _, _, _ = self.connections.pop(identifier)
            self.released += peak
        elif event == "census":
            count, reserved, live, control, header = values
            assert count == len(self.connections), "connection census lost ownership"
            assert reserved == self.reserved(), "TX census disagrees with reservation events"
            assert control == 28 * count, "control slots were not retained"
            assert header == 24 * count, "header slots were not retained"
            assert live <= reserved + control, "live frames exceed TX and control credit"
            self.censuses += 1
        else:
            raise AssertionError("unknown transport event: " + event)
        assert self.acquired == self.released + self.reserved(), "TX conservation failed"


def read(path):
    oracle = Oracle()
    content = path.read_text()
    complete = content[:content.rfind("\n") + 1]
    for line in complete.splitlines():
        oracle.accept(line)
    return oracle


def main():
    path = Path(sys.argv[1])
    deadline = time.monotonic() + 10
    while True:
        oracle = read(path)
        if oracle.seen and not oracle.connections and oracle.censuses:
            assert oracle.acquired == oracle.released
            print(json.dumps({"tx_acquired": oracle.acquired,
                              "tx_released": oracle.released,
                              "tx_peak": oracle.peak,
                              "slot_peak": oracle.slot_peak,
                              "connections": len(oracle.seen)}, sort_keys=True))
            return
        if time.monotonic() >= deadline:
            raise AssertionError("missing observation or unreleased reservations: " +
                                 repr(oracle.connections))
        time.sleep(0.01)


if __name__ == "__main__":
    main()
