# roc-uuid

UUIDs for [Roc](https://www.roc-lang.org), following
[RFC 9562](https://www.rfc-editor.org/rfc/rfc9562).

- Parse and print UUIDs, with errors that say what's wrong and where
- Make version 4 (random), 7 (random, sorted by time), 8 (custom) and 3
  (name-based) UUIDs
- Keep version 7 UUIDs in order within a millisecond with `v7_after`
- Read a UUID's version, variant and version 7 timestamp
- Works on every platform, because it never reads a clock or random
  number generator itself

Written for the Roc 0.1.0_RC1 compiler.

## Usage

```roc
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	uuid: "RELEASE_URL",
}

import pf.Random
import pf.Stdout
import pf.Utc
import uuid.Uuid

main! = |_args| {
	bits = Uuid.random_bits!(Random.seed_u64!)?
	Stdout.line!(Uuid.v4(bits).to_str())?

	now = Utc.now!().to_millis_since_epoch().to_u64_wrap()
	Stdout.line!(Uuid.v7(now, bits).to_str())?
	Ok({})
}
```

### Randomness and time

This package never asks the platform for anything. You give it random bits
and the time, so it works the same on every platform and in tests.

There are two ways to get random bits. With an effectful source, such as
basic-cli's `Random.seed_u64!`, pass the function in and its error passes
through.

```roc
bits = Uuid.random_bits!(Random.seed_u64!)?
```

With a pure generator, such as [roc-prng](https://github.com/niclas-ahden/roc-prng)'s
`Seed`, thread it through a mutable variable. Any type with a
`step : g -> (U64, g)` method works.

```roc
var $seed = Random.seed(Utc.now!().to_u64_wrap())
(bits, $seed) = Uuid.random_bits($seed)
```

Any `U128` works too, which is handy in tests.

### Making UUIDs

```roc
Uuid.v4(bits)                 # 122 random bits
Uuid.v7(unix_ms, bits)        # the time in milliseconds, then 74 random bits
Uuid.v8(bits)                 # your own 122 bits
Uuid.v3(Uuid.namespace_dns, "www.example.com".to_utf8())
```

Use version 7 for database keys, because new keys land at the end of the
index. Use version 4 when an ID shouldn't reveal when it was made.

Version 7 UUIDs from different milliseconds sort by time. To also keep them
in order within a millisecond, or when the clock goes backwards, make each
one from the last with `v7_after`. It counts up in the 12 bits after the
timestamp, following RFC 9562 section 6.2, method 1.

```roc
var $last = Uuid.nil
for _ in rows {
	$last = Uuid.v7_after($last, now, Uuid.random_bits!(Random.seed_u64!)?)
	# ...
}
```

The only state is the last UUID, so you can pick up from one you stored,
like the newest row in a table.

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
byte offset in the text.

### Everything else

- `version()` gives `V1` to `V8`, or `Other(n)` for anything else, and
  `variant()` gives `Ncs`, `Rfc9562`, `Microsoft` or `Future`
- `unix_ms()` reads the timestamp back out of a version 7 UUID
- `to_bytes()` and `from_bytes()` use the 16 bytes in network byte order,
  and `to_u128()` and `from_u128()` the 128 bits
- `Uuid.nil` and `Uuid.max` are the all-zeros and all-ones UUIDs
- `==`, `<` and the rest compare in RFC 9562 byte order, which is time order
  for version 7, and a `Uuid` works as a `Dict` key

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

The tests include every example UUID in RFC 9562, checks of every version
nibble and variant boundary, round trips through text, bytes and `U128`,
errors at every position, and `v7_after` over thousands of clock readings
that repeat and go backwards.

`just diff` checks the package against Python's uuid module, which shares no
code with it. For each random 128-bit value it compares the text, URN,
bytes, version and variant with `uuid.UUID`, the `v4`, `v7` and `v8` results
with Python setting the same bits, and `v3` with `uuid.uuid3`. It also
parses the value spelled every supported way, with one character changed,
and with random edits, and checks that we accept exactly the documented
forms and read them as Python does. Then it parses UUIDs Python made itself,
and checks that `random_bits!` gives distinct version 4 UUIDs. CI runs 5000
inputs.

The [roc-fuzz](https://github.com/lukewilliamboswell/roc-fuzz) target checks
that parsing arbitrary text never misreports an error's position, that
generated UUIDs always have the right version, variant and timestamp, and
that `v7_after` always moves forward.

CI runs all of this on Linux and macOS for every push to main and every pull
request.

## Releasing

Push a version tag such as `0.1.0`. The release workflow runs the tests and
the differential test, bundles `package/` with `just bundle`, and attaches
the archive to a GitHub release whose notes give the package URL.
