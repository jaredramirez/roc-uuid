"""Compare roc-uuid against Python's uuid module on random inputs.

Usage: python3 diff/diff.py ORACLE [--count N] [--seed N]

ORACLE is the built diff/oracle.roc. This script makes random cases, sends
them to the oracle in one batch, and checks every answer against Python's
uuid module (3.14, for uuid8) and the RFC 9562 grammar written out below as
regular expressions, which don't share any code with the package.
"""

import argparse
import random
import re
import subprocess
import sys
import uuid

HEX = "0123456789abcdefABCDEF"
CANONICAL = re.compile(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
HEX32 = re.compile(r"[0-9a-fA-F]{32}")
URN = re.compile(r"[uU][rR][nN]:[uU][uU][iI][dD]:")

VARIANTS = {
    uuid.RESERVED_NCS: "ncs",
    uuid.RFC_4122: "rfc",
    uuid.RESERVED_MICROSOFT: "microsoft",
    uuid.RESERVED_FUTURE: "future",
}

NAMESPACES = [uuid.NAMESPACE_DNS, uuid.NAMESPACE_URL, uuid.NAMESPACE_OID, uuid.NAMESPACE_X500]


def lenient_grammar(text):
    """Whether text is one of the spellings from_str_lenient documents."""
    if URN.match(text):
        return bool(CANONICAL.fullmatch(text[9:]))
    if text.startswith("{") and text.endswith("}") and len(text) >= 2:
        text = text[1:-1]
    return bool(CANONICAL.fullmatch(text) or HEX32.fullmatch(text))


def python_parse(text):
    """Python's reading of a spelling we accept. Python only recognizes a
    lowercase urn:uuid: prefix, so lowercase it first."""
    if URN.match(text):
        text = "urn:uuid:" + text[9:]
    return uuid.UUID(text)


def is_hex(c):
    return chr(c) in HEX


def expected_strict(b, offset=0):
    """The documented result of from_str on bytes b: ("ok", None) or the
    error's (index, problem)"""
    for i, c in enumerate(b[:36]):
        if i in (8, 13, 18, 23):
            if c != ord("-"):
                return (offset + i, "hyphen")
        elif not is_hex(c):
            return (offset + i, "char")
    if len(b) != 36:
        return (offset + min(len(b), 36), "length")
    return ("ok", None)


def expected_hex(b, offset):
    for i, c in enumerate(b[:32]):
        if not is_hex(c):
            return (offset + i, "char")
    if len(b) != 32:
        return (offset + min(len(b), 32), "length")
    return ("ok", None)


def expected_any(b, offset):
    return expected_strict(b, offset) if len(b) > 8 and b[8] == ord("-") else expected_hex(b, offset)


def expected_lenient(b):
    """The documented result of from_str_lenient on bytes b"""
    if b.startswith(b"{"):
        if len(b) >= 2 and b.endswith(b"}"):
            return expected_any(b[1:-1], 1)
        inner = expected_any(b[1:], 1)
        return (len(b), "length") if inner[0] == "ok" else inner
    if b[:9].lower() == b"urn:uuid:":
        return expected_strict(b[9:], 9)
    return expected_any(b, 0)


def next_v7(previous, ms, bits):
    """RFC 9562 section 6.2 method 1, as documented: a 12-bit counter after
    the timestamp, seeded from 11 random bits"""
    ms &= 2**48 - 1
    p = uuid.UUID(int=previous)
    fresh = (bits >> 62) & 0x7FF
    if p.variant == uuid.RFC_4122 and p.version == 7 and ms <= previous >> 80:
        counter = (previous >> 64) & 0xFFF
        if counter < 0xFFF:
            ts, counter = previous >> 80, counter + 1
        else:
            ts, counter = ((previous >> 80) + 1) & (2**48 - 1), fresh
    else:
        ts, counter = ms, fresh
    return uuid.UUID(int=(ts << 80) | (counter << 64) | (bits & (2**62 - 1)), version=7)


def random_value(rng):
    """Mostly uniform 128-bit values, plus values with every interesting
    version nibble and variant pattern"""
    n = rng.getrandbits(128)
    if rng.random() < 0.5:
        n = (n & ~(0xF << 76)) | (rng.randrange(16) << 76)
        n = (n & ~(0x7 << 61)) | (rng.randrange(8) << 61)
    return n


def spellings(rng, u):
    s = str(u)
    upper = s.upper()
    mixed = "".join(c.upper() if rng.random() < 0.5 else c for c in s)
    return [s, upper, mixed, "{" + s + "}", u.urn, u.urn.upper(), u.hex, "{" + u.hex + "}", u.hex.upper()]


def mutate(rng, text):
    chars = list(text)
    junk = HEX + "-{}:urnidURNID gGxz/@`[\t\né€"
    for _ in range(rng.randrange(1, 4)):
        op = rng.randrange(5)
        if op == 0 and chars:
            chars[rng.randrange(len(chars))] = rng.choice(junk)
        elif op == 1 and chars:
            del chars[rng.randrange(len(chars))]
        elif op == 2:
            chars.insert(rng.randrange(len(chars) + 1), rng.choice(junk))
        elif op == 3 and len(chars) > 1:
            i = rng.randrange(len(chars) - 1)
            chars[i], chars[i + 1] = chars[i + 1], chars[i]
        else:
            chars = chars[: rng.randrange(len(chars) + 1)]
    return "".join(chars)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("oracle")
    parser.add_argument("--count", type=int, default=2000)
    parser.add_argument("--seed", type=int, default=None)
    args = parser.parse_args()
    seed = args.seed if args.seed is not None else random.SystemRandom().randrange(2**63)
    rng = random.Random(seed)

    cases = []  # (line sent to the oracle, function checking its answer)

    for _ in range(args.count):
        n = random_value(rng)
        ms = rng.getrandbits(rng.choice([40, 48, 64]))
        u = uuid.UUID(int=n)

        def check_bits(answer, n=n, ms=ms, u=u):
            want = [
                str(u),
                u.urn,
                u.bytes.hex(),
                str((n >> 76) & 0xF) if u.variant != uuid.RFC_4122 else str(u.version),
                VARIANTS[u.variant],
                str(uuid.UUID(int=n, version=4)),
                str(uuid.UUID(int=((ms & (2**48 - 1)) << 80) | (n & (2**80 - 1)), version=7)),
                str(uuid.uuid8(n >> 80, (n >> 64) & 0xFFF, n & (2**62 - 1))),
            ]
            return answer.split(" ") == want, " ".join(want)

        cases.append((f"B {n:032x} {ms:x}", check_bits))

        namespace = rng.choice(NAMESPACES + [uuid.UUID(int=rng.getrandbits(128))])
        name = rng.randbytes(rng.choice([0, 1, 15, 16, 55, 56, 64, 100]))
        line = f"N3 {namespace.hex} {name.hex()}".rstrip()
        cases.append((line, lambda answer, ns=namespace, name=name: (answer == str(uuid.uuid3(ns, name)), str(uuid.uuid3(ns, name)))))
        line = f"N5 {namespace.hex} {name.hex()}".rstrip()
        cases.append((line, lambda answer, ns=namespace, name=name: (answer == str(uuid.uuid5(ns, name)), str(uuid.uuid5(ns, name)))))

        # Exactly one character changed, to any printable ASCII or a
        # non-ASCII character, so that a single wrong acceptance shows up
        single = []
        for t in rng.sample(spellings(rng, u), 3):
            i = rng.randrange(len(t))
            single.append(t[:i] + rng.choice([chr(rng.randrange(32, 127)), "\u00e9", "\u20ac"]) + t[i + 1 :])

        for text in spellings(rng, u) + single + [mutate(rng, t) for t in rng.sample(spellings(rng, u), 3)]:

            def check_parse(answer, text=text):
                b = text.encode()
                # Acceptance and values from Python's uuid and the grammar
                # above, error positions from the documented rules
                strict_err = expected_strict(b)
                lenient_err = expected_lenient(b)
                if CANONICAL.fullmatch(text):
                    want_strict = f"ok:{uuid.UUID(text)}"
                else:
                    want_strict = f"err:{strict_err[0]}:{strict_err[1]}"
                if lenient_grammar(text):
                    want_lenient = f"ok:{python_parse(text)}"
                else:
                    want_lenient = f"err:{lenient_err[0]}:{lenient_err[1]}"
                # The two descriptions of what's accepted must agree
                consistent = (strict_err[0] == "ok") == bool(CANONICAL.fullmatch(text)) and (lenient_err[0] == "ok") == lenient_grammar(text)
                return consistent and answer == f"{want_strict} {want_lenient}", f"{want_strict} {want_lenient}"

            cases.append((f"P {text.encode().hex()}".rstrip(), check_parse))

    # next_v7 against the model above, from random previous UUIDs: v7 ones
    # around the clock reading, ones with a full or nearly full counter, and
    # ones that aren't v7
    for _ in range(args.count):
        ms = rng.getrandbits(48)
        bits = rng.getrandbits(128)
        kind = rng.randrange(4)
        if kind == 0:
            previous = rng.getrandbits(128)
        else:
            prev_ms = (ms + rng.randrange(-3, 4)) % 2**48
            counter = rng.choice([0xFFF, 0xFFE, rng.getrandbits(12)])
            previous = uuid.UUID(int=(prev_ms << 80) | (counter << 64) | rng.getrandbits(64), version=7).int
        want = str(next_v7(previous, ms, bits))
        cases.append((f"A {previous:032x} {ms:x} {bits:032x}", lambda answer, want=want: (answer == want, want)))

    # The namespaces
    namespaces = " ".join(str(u) for u in NAMESPACES)
    cases.append(("NS", lambda answer: (answer == namespaces, namespaces)))

    # Version 1, 4, 6 and 7 UUIDs Python made itself parse back the same,
    # with their timestamps for version 7
    for make in [uuid.uuid1, uuid.uuid4, uuid.uuid6, uuid.uuid7]:
        for _ in range(50):
            u = make()
            cases.append(
                (
                    f"P {str(u).encode().hex()}",
                    lambda answer, u=u: (answer == f"ok:{u} ok:{u}", f"ok:{u} ok:{u}"),
                )
            )

    # The platform's randomness makes valid, distinct version 4 UUIDs
    random_answers = []
    for _ in range(20):

        def check_random(answer):
            random_answers.append(answer)
            u = uuid.UUID(answer)
            # The high and low 64 bits come from separate draws
            hi = (u.int >> 64) & ~(0xF << 12)
            lo = u.int & (2**62 - 1)
            return u.version == 4 and u.variant == uuid.RFC_4122 and hi & (2**62 - 1) != lo, "a random v4 from two draws"

        cases.append(("R", check_random))

    result = subprocess.run(
        [args.oracle], input="\n".join(line for line, _ in cases) + "\n", capture_output=True, text=True, check=True
    )
    answers = result.stdout.rstrip("\n").split("\n")
    if len(answers) != len(cases):
        print(f"expected {len(cases)} answers, got {len(answers)}", file=sys.stderr)
        return 1

    mismatches = 0
    for (line, check), answer in zip(cases, answers):
        ok, want = check(answer)
        if not ok:
            mismatches += 1
            if mismatches <= 10:
                print(f"MISMATCH for {line!r}\n  got:  {answer}\n  want: {want}", file=sys.stderr)
    if len(set(random_answers)) != len(random_answers):
        mismatches += 1
        print("Uuid.Gen.system repeated a UUID", file=sys.stderr)

    print(f"{len(cases)} cases from {args.count} random inputs, seed {seed}: {mismatches} mismatches")
    return 1 if mismatches else 0


if __name__ == "__main__":
    sys.exit(main())
