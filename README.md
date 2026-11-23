# roc-uuid

UUIDs for [Roc](https://www.roc-lang.org), following
[RFC 9562](https://www.rfc-editor.org/rfc/rfc9562).

- Parse and print UUIDs, with errors that say what's wrong and where
- Make version 4 (random), 7 (random, sorted by time), 8 (custom), and 3 and
  5 (name-based) UUIDs
- Keep version 7 UUIDs in order within a millisecond with `next_v7`
- Read a UUID's version, variant and version 7 timestamp
- Works on every platform, because it never reads a clock or random
  number generator itself

Written for the Roc 0.1.0_RC1 compiler.

## Usage

```roc
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	uuid: "https://github.com/jaredramirez/roc-uuid/releases/download/0.1.0/7sUeZ4HjfGX1ciy1cd1FxNLaeER87Mw8aocjyjwu4Rpt.tar.zst",
}

import pf.Random
import pf.Stdout
import pf.Utc
import uuid.Uuid

main! = |_args| {
	# Version 4: random
	id = Uuid.random!(Random.seed_u64!)?.v4()
	Stdout.line!("v4: ${id.to_str()}")?

	# Version 7: random, but sorted by time
	now = Utc.now!().to_millis_since_epoch()
	sorted_id = Uuid.random!(Random.seed_u64!)?.v7(now)
	Stdout.line!("v7: ${sorted_id.to_str()}")?

	# Parse one from text
	parsed = Uuid.from_str("f81d4fae-7dec-11d0-a765-00a0c91e6bf6")?
	Stdout.line!("parsed: ${parsed.to_str()}")?

	Ok({})
}
```

`examples/main.roc` runs every example in this README, and CI checks it.

### Randomness and time

This package never asks the platform for anything. You give it random bits
and the time, so it works the same on every platform and in tests.

Use fresh random bits for every UUID. Reusing them makes UUIDs share bits,
so one gives away part of another.

Random bits are a `Uuid.Random`, and `v4` and `v7` are methods on it.
There are two ways to get one. With an effectful source, such as basic-cli's
`Random.seed_u64!`, pass the function to `random!` and its error passes
through. This is the one to use for IDs, because basic-cli reads the
operating system's secure random number generator, as RFC 9562 recommends.

```roc
id = Uuid.random!(Random.seed_u64!)?.v4()
```

With a pure generator, such as [roc-prng](https://github.com/niclas-ahden/roc-prng)'s
`Seed`, thread it through a mutable variable. Any type with a
`step : g -> (U64, g)` method works. Seed it from the platform's randomness,
not the clock, since two processes seeded at the same moment would make the
same UUIDs. roc-prng's generator isn't cryptographically secure, so prefer
`random!` when UUIDs must be hard to guess.

```roc
import prng.Random as Prng

var $seed = Prng.seed(Random.seed_u64!()?)
(first, $seed) = Uuid.random($seed)
(second, $seed) = Uuid.random($seed)
```

`Uuid.Random.from_bits` takes any `U128`, which is handy in tests.

Timestamps are Unix milliseconds, in any integer type from `U64` up, so
basic-cli's `Utc.now!().to_millis_since_epoch()` works as it is. Only 48
bits fit, which lasts until the year 10889, and anything above that is
dropped without an error, so a timestamp in nanoseconds or seconds gives a
wrong but valid-looking UUID. A time before 1970 counts as 0.

### Making UUIDs

```roc
bits.v4()                     # 122 random bits
bits.v7(unix_ms)              # the time in milliseconds, then 74 random bits
Uuid.v8(your_bits)            # your own 122 bits, from a U128
Uuid.v5(Uuid.namespace_dns, "www.example.com".to_utf8())
Uuid.v3(Uuid.namespace_dns, "www.example.com".to_utf8())
```

Use version 7 for database keys, because new keys land at the end of the
index. Use version 4 when an ID shouldn't reveal when it was made. Use
version 5 when the same name should always give the same UUID, and version 3
only to match existing version 3 IDs. Names are bytes, and the namespaces
from RFC 9562 are `namespace_dns`, `namespace_url`, `namespace_oid` and
`namespace_x500`. Version 5 uses [roc-sha1](https://github.com/jaredramirez/roc-sha1)
and version 3 [roc-md5](https://github.com/niclas-ahden/roc-md5).

Version 7 UUIDs from different milliseconds sort by time. To also keep them
in order within a millisecond, or when the clock goes backwards, make each
one from the last with `next_v7`. It counts up in the 12 bits after the
timestamp, following RFC 9562 section 6.2, method 1.

```roc
var $last = Uuid.nil
for _ in rows {
	bits = Uuid.random!(Random.seed_u64!)?
	$last = $last.next_v7(now, bits)
	# ...
}
```

The only state is the last UUID, so you can pick up from one you stored,
like the newest row in a table. Because `next_v7` always sorts after the UUID
you give it, a UUID from the future, say from a clock that was ahead or a
timestamp in the wrong unit, holds every later one at that future time. Only
pass UUIDs you made yourself or otherwise trust.

### Parsing and printing

```roc
Uuid.from_str("f81d4fae-7dec-11d0-a765-00a0c91e6bf6")    # Ok(...)
Uuid.from_str("f81d4fae7dec11d0a76500a0c91e6bf6")
# Err(InvalidUuid({ index: 8, problem: ExpectedHyphen }))

Uuid.from_str_lenient("{F81D4FAE-7DEC-11D0-A765-00A0C91E6BF6}")  # Ok(...)

id.to_str()   # "f81d4fae-7dec-11d0-a765-00a0c91e6bf6"
id.to_urn()   # "urn:uuid:f81d4fae-7dec-11d0-a765-00a0c91e6bf6"
```

`from_str` takes only the canonical form, in either case. `from_str_lenient`
also takes braces, a `urn:uuid:` prefix, and 32 hex digits without hyphens.
Errors are `InvalidUuid({ index, problem })`, where `problem` is
`InvalidChar(byte)`, `ExpectedHyphen` or `WrongLength`, and `index` is the
byte offset in the text. The types are `Uuid.ParseErr`, `Uuid.Version` and
`Uuid.Variant`.

### Everything else

- `version()` gives `V1` to `V8`, or `Other(n)` for any other nibble and for
  UUIDs of other variants, which RFC 9562 doesn't define versions for, and
  `variant()` gives `Ncs`, `Rfc9562`, `Microsoft` or `Future`
- `unix_ms()` reads the timestamp back out of a version 7 UUID
- `to_bytes()` and `from_bytes()` use the 16 bytes in network byte order,
  and `to_u128()` and `from_u128()` the 128 bits
- `Uuid.nil` and `Uuid.max` are the all-zeros and all-ones UUIDs
- `==`, `<`, `List.sort` and the rest compare in RFC 9562 byte order, which
  is time order for version 7, and a `Uuid` works as a `Dict` key

## Development

Development needs [Nix](https://nixos.org/download/) and
[devenv 2.x](https://devenv.sh/getting-started/), which pin Roc 0.1.0_RC1
and Python 3.14.

```sh
devenv shell
just check
just test       # the tests, with the interpreter
just test-all   # the tests, with every backend
just diff       # compare against Python's uuid module
just fuzz 30    # check the fuzz examples, then explore for 30 seconds
just bench      # nanoseconds per call
```

`devenv test` runs the checks, tests and a formatting check.

The tests include every example UUID in RFC 9562, the namespaces, checks of
every version nibble and variant boundary, round trips through text, bytes
and `U128`, errors at every position, and `next_v7` over thousands of clock
readings that repeat and go backwards, plus its counter at every edge.

`just diff` checks the package against Python's uuid module, which shares no
code with it. For each random 128-bit value it compares the text, URN,
bytes, version and variant with `uuid.UUID`, the `v4`, `v7` and `v8` results
with Python setting the same bits, and `v3` and `v5` with `uuid.uuid3` and
`uuid.uuid5`. It parses the value spelled every supported way, with one
character changed, and with random edits. It checks that we accept exactly
the documented forms, read them as Python does, and report each error at
the position and with the problem the documented rules give. It compares
`next_v7` with a separate model of RFC 9562 method 1, from previous UUIDs
around the clock and with full counters. Then it parses UUIDs Python made
itself, checks the namespaces, and checks that `random!` gives distinct
version 4 UUIDs from two separate draws. CI runs 5000 inputs.

The [roc-fuzz](https://github.com/lukewilliamboswell/roc-fuzz) target parses
arbitrary text and checks that accepted text round trips and that errors
point at a plausible place: an invalid character at that byte, a missing
hyphen at a hyphen position, and a wrong length at the end of the text or of
a UUID. It also checks that generated UUIDs always have the right version,
variant and timestamp, and that `next_v7` always moves forward.

CI runs all of this on Linux and macOS for every push to main and every pull
request.

## Releasing

Push a version tag such as `0.1.0`. The release workflow runs the tests and
the differential test, bundles `package/` with `just bundle`, and attaches
the archive to a GitHub release whose notes give the package URL.
