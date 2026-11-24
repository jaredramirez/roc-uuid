"""Times the same work as bench/main.roc with Python's uuid module and prints
`operation: NS` lines, the fastest nanoseconds per call. Python's uuid7 reads
the clock and the OS's random numbers itself, so it's left out.
"""

import time
import uuid

COUNT = 10_000
MULTIPLIER = 0x9E37_79B9_7F4A_7C15_F39C_C060_5CED_C835
MASK = 2**128 - 1


def best(f):
    """The fastest of 50 batches, in nanoseconds per call"""
    fastest = None
    for _ in range(52):
        start = time.perf_counter_ns()
        f()
        ns = time.perf_counter_ns() - start
        fastest = ns if fastest is None else min(fastest, ns)
    return fastest / COUNT


ids = [uuid.UUID(int=(i * MULTIPLIER) & MASK, version=4) for i in range(COUNT)]
texts = [str(i) for i in ids]
name = b"www.example.com"
rows = [
    ("from_str", best(lambda: [uuid.UUID(t) for t in texts])),
    ("to_str", best(lambda: [str(i) for i in ids])),
    ("v4", best(lambda: [uuid.UUID(int=i.int, version=4) for i in ids])),
    ("v8", best(lambda: [uuid.uuid8(i.int >> 80, (i.int >> 64) & 0xFFF, i.int & (2**62 - 1)) for i in ids])),
    ("v5", best(lambda: [uuid.uuid5(i, name) for i in ids])),
    ("v3", best(lambda: [uuid.uuid3(i, name) for i in ids])),
]
for label, ns in rows:
    print(f"{label}: {ns:.1f}")
