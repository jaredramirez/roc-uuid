## Universally unique identifiers, as specified by
## [RFC 9562](https://www.rfc-editor.org/rfc/rfc9562).
##
## A `Uuid` is 128 bits. Parse one with `from_str`, write one with `to_str`,
## and make new ones with `v4` (random), `v7` (random, sorted by creation
## time), `v8` (your own layout), or `v3` and `v5` (derived from a name).
##
## This package never reads a clock or a random number generator itself, so
## it works on every platform. You pass in random bits and timestamps, and
## `random_bits!` and `random_bits` get the bits from whatever your platform
## or a pseudo-random generator provides.

## A problem with the text given to `from_str` or `from_str_lenient`, and
## the byte offset where it was found:
##
## - `InvalidChar(byte)` a byte that can't appear there.
## - `ExpectedHyphen` a hyphen is missing at one of the four places the
##   canonical form has one.
## - `WrongLength` the text is too short or too long. The index is where the
##   text ended, or the first byte past the end of a UUID.
import md5.Md5

ParseErr : [InvalidUuid({ index : U64, problem : [InvalidChar(U8), ExpectedHyphen, WrongLength] })]

## The version, from the 4 bits RFC 9562 sets aside for it. The nil UUID
## reports `Other(0)` and the max UUID `Other(15)`.
Version : [V1, V2, V3, V4, V5, V6, V7, V8, Other(U8)]

## The variant, from the top bits of the 9th byte. Every UUID this package
## makes is `Rfc9562`.
Variant : [Ncs, Rfc9562, Microsoft, Future]

Uuid :: [Bits(U128)].{
	is_eq : _
	to_hash : _

	## The nil UUID, `00000000-0000-0000-0000-000000000000`.
	nil : Uuid
	nil = Bits(0)

	## The max UUID, `ffffffff-ffff-ffff-ffff-ffffffffffff`.
	max : Uuid
	max = Bits(0xFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF)

	## A UUID from its 128 bits, most significant first, as is. This sets no
	## version or variant bits; use `v4`, `v7` or `v8` to make a new UUID.
	from_u128 : U128 -> Uuid
	from_u128 = |bits| Bits(bits)

	## The UUID's 128 bits, most significant first.
	to_u128 : Uuid -> U128
	to_u128 = |Bits(bits)| bits

	## A UUID from exactly 16 bytes, in network byte order (big-endian), as
	## RFC 9562 lays them out.
	from_bytes : List(U8) -> Try(Uuid, [WrongLength(U64)])
	from_bytes = |bytes|
		if bytes.len() == 16 {
			Ok(Bits(bytes.fold(0, |bits, byte| bits.shl_wrap(8).bitwise_or(byte.to_u128()))))
		} else {
			Err(WrongLength(bytes.len()))
		}

	## The UUID's 16 bytes, in network byte order (big-endian).
	to_bytes : Uuid -> List(U8)
	to_bytes = |Bits(bits)|
		List.from_iter((0.U8).until(16)).map(|i| bits.shr_zf_wrap(120 - i * 8).to_u8_wrap())

	## Parse the canonical form, `f81d4fae-7dec-11d0-a765-00a0c91e6bf6`: 32
	## hexadecimal digits in groups of 8, 4, 4, 4 and 12, separated by
	## hyphens. Letters can be either case, as RFC 9562 requires.
	##
	## ```roc
	## Uuid.from_str("f81d4fae-7dec-11d0-a765-00a0c91e6bf6") # Ok(...)
	## Uuid.from_str("f81d4fae7dec11d0a76500a0c91e6bf6")     # Err(InvalidUuid({ index: 8, problem: ExpectedHyphen }))
	## ```
	from_str : Str -> Try(Uuid, ParseErr)
	from_str = |text| parse_canonical(text.to_utf8(), 0)

	## Parse the canonical form, or any of the other spellings in common use:
	##
	## - wrapped in braces, `{f81d4fae-7dec-11d0-a765-00a0c91e6bf6}`, as on
	##   Windows
	## - after `urn:uuid:` (in any case), as in RFC 9562's URN form
	## - 32 hexadecimal digits without hyphens
	##
	## Error indexes are offsets into the whole text.
	from_str_lenient : Str -> Try(Uuid, ParseErr)
	from_str_lenient = |text| {
		bytes = text.to_utf8()
		len = bytes.len()
		if bytes.starts_with(['{']) {
			match bytes.last() {
				Ok('}') => parse_any(bytes.sublist({ start: 1, len: len - 2 }), 1)
				_ =>
				# Report the problem at the end, past the digits
					match parse_any(bytes.drop_first(1), 1) {
						Ok(_) => Err(InvalidUuid({ index: len, problem: WrongLength }))
						Err(err) => Err(err)
					}
			}
		} else if has_urn_prefix(bytes) {
			parse_canonical(bytes.drop_first(9), 9)
		} else {
			parse_any(bytes, 0)
		}
	}

	## The canonical form, in lowercase as RFC 9562 requires:
	## `f81d4fae-7dec-11d0-a765-00a0c91e6bf6`.
	to_str : Uuid -> Str
	to_str = |Bits(bits)| {
		var $out = List.with_capacity(36)
		for i in List.from_iter((0.U8).until(32)) {
			if i == 8 or i == 12 or i == 16 or i == 20 {
				$out = $out.append('-')
			}
			$out = $out.append(hex_digit(bits.shr_zf_wrap(124 - i * 4).to_u8_wrap().bitwise_and(0xF)))
		}
		Str.from_utf8_lossy($out)
	}

	## The URN form, `urn:uuid:f81d4fae-7dec-11d0-a765-00a0c91e6bf6`.
	to_urn : Uuid -> Str
	to_urn = |uuid| "urn:uuid:".concat(uuid.to_str())

	## Shows the canonical form, as `Uuid(f81d4fae-7dec-11d0-a765-00a0c91e6bf6)`.
	to_inspect : Uuid -> Str
	to_inspect = |uuid| "Uuid(${uuid.to_str()})"

	## The version, from bits 48 to 51.
	version : Uuid -> Version
	version = |Bits(bits)|
		match bits.shr_zf_wrap(76).to_u8_wrap().bitwise_and(0xF) {
			1 => V1
			2 => V2
			3 => V3
			4 => V4
			5 => V5
			6 => V6
			7 => V7
			8 => V8
			other => Other(other)
		}

	## The variant, from the top bits of byte 8.
	variant : Uuid -> Variant
	variant = |Bits(bits)| {
		top = bits.shr_zf_wrap(61).to_u8_wrap().bitwise_and(0x7)
		if top < 4 {
			Ncs
		} else if top < 6 {
			Rfc9562
		} else if top == 6 {
			Microsoft
		} else {
			Future
		}
	}

	## The Unix timestamp in milliseconds a version 7 UUID starts with.
	unix_ms : Uuid -> Try(U64, [NotV7])
	unix_ms = |uuid|
		match (uuid.version(), uuid.variant()) {
			(V7, Rfc9562) => Ok(uuid.to_u128().shr_zf_wrap(80).to_u64_wrap())
			_ => Err(NotV7)
		}

	## A version 4 UUID: 122 random bits. `bits` should be random, from
	## `random_bits!` or `random_bits`; its 6 bits at the version and variant
	## positions are replaced.
	##
	## ```roc
	## id = Uuid.v4(Uuid.random_bits!(Random.seed_u64!)?)
	## ```
	v4 : U128 -> Uuid
	v4 = |bits| with_version(bits, 4)

	## A version 7 UUID: the Unix timestamp in milliseconds, then 74 random
	## bits. UUIDs made in different milliseconds sort by when they were made;
	## use `v7_after` to also keep order within a millisecond.
	##
	## Only the low 48 bits of `ms` fit, which covers dates until the year
	## 10889. The random bits are the low 80 bits of `bits`, with the version
	## and variant positions replaced.
	v7 : U64, U128 -> Uuid
	v7 = |ms, bits| {
		time = ms.to_u128().bitwise_and(0xFFFF_FFFF_FFFF).shl_wrap(80)
		with_version(time.bitwise_or(bits.bitwise_and(low_80_bits)), 7)
	}

	## A version 7 UUID that sorts after `previous`, even when it's made in
	## the same millisecond or the clock has gone backwards, following
	## RFC 9562 section 6.2, method 1: the 12 bits after the timestamp count
	## up within a millisecond.
	##
	## When `previous` is from an earlier millisecond, or isn't a version 7
	## UUID (such as `Uuid.nil` to start), this is `v7` with a random counter
	## that leaves room to count. Otherwise it keeps the timestamp of
	## `previous` and adds 1 to its counter, moving to the next millisecond if
	## the counter is full.
	##
	## ```roc
	## var $last = Uuid.nil
	## $last = Uuid.v7_after($last, unix_ms, bits)
	## ```
	v7_after : Uuid, U64, U128 -> Uuid
	v7_after = |previous, ms, bits| {
		time = ms.bitwise_and(0xFFFF_FFFF_FFFF)
		match previous.unix_ms() {
			Ok(previous_ms) if time <= previous_ms => {
				counter = previous.to_u128().shr_zf_wrap(64).bitwise_and(0xFFF)
				if counter < 0xFFF {
					v7_parts(previous_ms, counter + 1, bits)
				} else {
					# Wraps to 0 only after the year 10889
					v7_parts(previous_ms.plus_wrap(1).bitwise_and(0xFFFF_FFFF_FFFF), fresh_counter(bits), bits)
				}
			}
			_ => v7_parts(time, fresh_counter(bits), bits)
		}
	}

	## A version 8 UUID: 122 bits laid out however you need. `bits` keeps
	## everything but the 6 bits at the version and variant positions.
	v8 : U128 -> Uuid
	v8 = |bits| with_version(bits, 8)

	## A version 3 UUID: the MD5 hash of `namespace` followed by `name`, so the
	## same name in the same namespace always gives the same UUID. RFC 9562
	## prefers `v5`; use `v3` when you need to match existing version 3 IDs.
	##
	## ```roc
	## Uuid.v3(Uuid.namespace_dns, "www.example.com".to_utf8())
	## # 5df41881-3aed-3515-88a7-2f4a814cf09e
	## ```
	v3 : Uuid, List(U8) -> Uuid
	v3 = |namespace, name| name_based(Md5.hash(namespace.to_bytes().concat(name)).to_bytes(), 3)

	## The namespace for fully qualified domain names, for `v3` and `v5`.
	namespace_dns : Uuid
	namespace_dns = Bits(0x6ba7_b810_9dad_11d1_80b4_00c0_4fd4_30c8)

	## The namespace for URLs, for `v3` and `v5`.
	namespace_url : Uuid
	namespace_url = Bits(0x6ba7_b811_9dad_11d1_80b4_00c0_4fd4_30c8)

	## The namespace for ISO object identifiers (OIDs), for `v3` and `v5`.
	namespace_oid : Uuid
	namespace_oid = Bits(0x6ba7_b812_9dad_11d1_80b4_00c0_4fd4_30c8)

	## The namespace for X.500 distinguished names, for `v3` and `v5`.
	namespace_x500 : Uuid
	namespace_x500 = Bits(0x6ba7_b814_9dad_11d1_80b4_00c0_4fd4_30c8)

	## 128 random bits from an effectful source of 64-bit numbers, such as
	## basic-cli's `Random.seed_u64!`. Its error passes through.
	##
	## ```roc
	## bits = Uuid.random_bits!(Random.seed_u64!)?
	## ```
	random_bits! : (() => Try(U64, err)) => Try(U128, err)
	random_bits! = |next!| {
		hi = next!()?
		lo = next!()?
		Ok(join(hi, lo))
	}

	## 128 random bits from a pure pseudo-random generator, and the generator
	## to use next. Works with any generator that has a
	## `step : g -> (U64, g)` method, such as roc-prng's `Seed`.
	##
	## ```roc
	## var $seed = Random.seed(Utc.now!().to_u64_wrap())
	## (bits, $seed) = Uuid.random_bits($seed)
	## ```
	random_bits : g -> (U128, g) where [g.step : g -> (U64, g)]
	random_bits = |generator| {
		(hi, after_hi) = generator.step()
		(lo, after_lo) = after_hi.step()
		(join(hi, lo), after_lo)
	}

	## Compare in RFC 9562 byte order, which for version 7 is creation order.
	is_lt : Uuid, Uuid -> Bool
	is_lt = |a, b| a.to_u128() < b.to_u128()

	is_lte : Uuid, Uuid -> Bool
	is_lte = |a, b| a.to_u128() <= b.to_u128()

	is_gt : Uuid, Uuid -> Bool
	is_gt = |a, b| a.to_u128() > b.to_u128()

	is_gte : Uuid, Uuid -> Bool
	is_gte = |a, b| a.to_u128() >= b.to_u128()
}

# Everything below is private to this module

## `bits` with the 4 version bits set to `version` and the 2 variant bits
## set to `10`
with_version : U128, U128 -> Uuid
with_version = |bits, version|
	Bits(
		bits
			.bitwise_and(0xFFFF_FFFF_FFFF_0FFF_3FFF_FFFF_FFFF_FFFF)
			.bitwise_or(version.shl_wrap(76))
			.bitwise_or(0x8000_0000_0000_0000),
	)

## A name-based UUID from the first 16 bytes of a hash
name_based : List(U8), U128 -> Uuid
name_based = |hash, version|
	with_version(hash.take_first(16).fold(0, |bits, byte| bits.shl_wrap(8).bitwise_or(byte.to_u128())), version)

low_80_bits : U128
low_80_bits = 0xFFFF_FFFF_FFFF_FFFF_FFFF

## A version 7 UUID from its timestamp, its 12-bit counter in `rand_a`, and
## random bits for the 62 bits of `rand_b`
v7_parts : U64, U128, U128 -> Uuid
v7_parts = |unix_ms, counter, bits|
	with_version(
		unix_ms.to_u128().shl_wrap(80)
			.bitwise_or(counter.shl_wrap(64))
			.bitwise_or(bits.bitwise_and(0x3FFF_FFFF_FFFF_FFFF)),
		7,
	)

## A random start for the counter, from the 11 bits of `bits` above `rand_b`,
## so that at least 2048 more UUIDs fit in the same millisecond
fresh_counter : U128 -> U128
fresh_counter = |bits| bits.shr_zf_wrap(62).bitwise_and(0x7FF)

join : U64, U64 -> U128
join = |hi, lo| hi.to_u128().shl_wrap(64).bitwise_or(lo.to_u128())

hex_digit : U8 -> U8
hex_digit = |n| if (n < 10) '0' + n else 'a' + n - 10

## The value of a hexadecimal digit in either case
hex_value : U8 -> Try(U8, [NotHex])
hex_value = |c|
	if c >= '0' and c <= '9' {
		Ok(c - '0')
	} else if c >= 'a' and c <= 'f' {
		Ok(c - 'a' + 10)
	} else if c >= 'A' and c <= 'F' {
		Ok(c - 'A' + 10)
	} else {
		Err(NotHex)
	}

## Whether `bytes` starts with `urn:uuid:` in any case
has_urn_prefix : List(U8) -> Bool
has_urn_prefix = |bytes|
	bytes.take_first(9).map(|c| if (c >= 'A' and c <= 'Z') c + 32 else c) == "urn:uuid:".to_utf8()

## Parse the canonical form or 32 hexadecimal digits, choosing by whether a
## hyphen comes after the first 8 digits. `offset` is where `bytes` starts in
## the whole text, for error indexes.
parse_any : List(U8), U64 -> Try(Uuid, ParseErr)
parse_any = |bytes, offset|
	if bytes.get(8) == Ok('-') {
		parse_canonical(bytes, offset)
	} else {
		parse_hex(bytes, offset)
	}

## Parse exactly 36 bytes of canonical form
parse_canonical : List(U8), U64 -> Try(Uuid, ParseErr)
parse_canonical = |bytes, offset| {
	var $bits = 0.U128
	var $index = 0.U64
	var $problem = None
	for c in bytes.take_first(36) {
		if $index == 8 or $index == 13 or $index == 18 or $index == 23 {
			if c != '-' {
				$problem = Found(ExpectedHyphen)
				break
			}
		} else {
			match hex_value(c) {
				Ok(v) => {
					$bits = $bits.shl_wrap(4).bitwise_or(v.to_u128())
				}
				Err(NotHex) => {
					$problem = Found(InvalidChar(c))
					break
				}
			}
		}
		$index = $index + 1
	}
	match $problem {
		Found(problem) => Err(InvalidUuid({ index: offset + $index, problem }))
		None =>
			if bytes.len() == 36 {
				Ok(Bits($bits))
			} else {
				Err(InvalidUuid({ index: offset + bytes.len().min(36), problem: WrongLength }))
			}
	}
}

## Parse exactly 32 hexadecimal digits
parse_hex : List(U8), U64 -> Try(Uuid, ParseErr)
parse_hex = |bytes, offset| {
	var $bits = 0.U128
	var $index = 0.U64
	var $bad = None
	for c in bytes.take_first(32) {
		match hex_value(c) {
			Ok(v) => {
				$bits = $bits.shl_wrap(4).bitwise_or(v.to_u128())
			}
			Err(NotHex) => {
				$bad = Found(c)
				break
			}
		}
		$index = $index + 1
	}
	match $bad {
		Found(c) => Err(InvalidUuid({ index: offset + $index, problem: InvalidChar(c) }))
		None =>
			if bytes.len() == 32 {
				Ok(Bits($bits))
			} else {
				Err(InvalidUuid({ index: offset + bytes.len().min(32), problem: WrongLength }))
			}
	}
}

# --- Tests ---

## A UUID from text the tests know is valid
parse : Str -> Uuid
parse = |text|
	match Uuid.from_str_lenient(text) {
		Ok(uuid) => uuid
		Err(_) => crash "the tests only parse valid UUIDs: ${text}"
	}

## A tiny deterministic generator for the property tests (SplitMix64), with
## the same `step` shape as roc-prng's `Seed`
Gen := [Gen(U64)].{
	step : Gen -> (U64, Gen)
	step = |Gen(state)| {
		next = state.plus_wrap(0x9E37_79B9_7F4A_7C15)
		z1 = next.bitwise_xor(next.shr_zf_wrap(30)).times_wrap(0xBF58_476D_1CE4_E5B9)
		z2 = z1.bitwise_xor(z1.shr_zf_wrap(27)).times_wrap(0x94D0_49BB_1331_11EB)
		(z2.bitwise_xor(z2.shr_zf_wrap(31)), Gen(next))
	}
}

gen : U64 -> Gen
gen = |seed| Gen(seed)

## `count` pseudo-random 128-bit values
samples : U64, U64 -> List(U128)
samples = |count, seed| {
	var $gen = gen(seed)
	var $out = []
	for _ in List.from_iter((0.U64).until(count)) {
		(bits, next) = Uuid.random_bits($gen)
		$gen = next
		$out = $out.append(bits)
	}
	$out
}

# RFC 9562 appendix A and B: every example parses, prints back the same
# (in lowercase), and reports its version and the RFC variant
rfc_examples = [
	("C232AB00-9414-11EC-B3C8-9F6BDECED846", V1),
	("5df41881-3aed-3515-88a7-2f4a814cf09e", V3),
	("919108f7-52d1-4320-9bac-f847db4148a8", V4),
	("2ed6657d-e927-568b-95e1-2665a8aea6a2", V5),
	("1EC9414C-232A-6B00-B3C8-9F6BDECED846", V6),
	("017F22E2-79B0-7CC3-98C4-DC0C0C07398F", V7),
	("2489E9AD-2EE2-8E00-8EC9-32D5F69181C0", V8),
	("5c146b14-3c52-8afd-938a-375d0df1fbf6", V8),
]

expect rfc_examples.all(
	|(text, version)|
		match Uuid.from_str(text) {
			Ok(uuid) => uuid.to_str() == lowercase(text) and uuid.version() == version and uuid.variant() == Rfc9562
			Err(_) => False
		},
)

lowercase : Str -> Str
lowercase = |text| Str.from_utf8_lossy(text.to_utf8().map(|c| if (c >= 'A' and c <= 'Z') c + 32 else c))

# The v4 and v7 examples come out of `v4` and `v7` from their bits, even when
# the version and variant positions hold something else
expect Uuid.v4(0x9191_08f7_52d1_f320_5bac_f847_db41_48a8) == parse("919108f7-52d1-4320-9bac-f847db4148a8")

expect Uuid.v7(0x017F_22E2_79B0, 0xFFFF_FFFF_FFFF_0CC3_D8C4_DC0C_0C07_398F) == parse("017F22E2-79B0-7CC3-98C4-DC0C0C07398F")

expect parse("017F22E2-79B0-7CC3-98C4-DC0C0C07398F").unix_ms() == Ok(0x017F_22E2_79B0)

expect parse("919108f7-52d1-4320-9bac-f847db4148a8").unix_ms() == Err(NotV7)

# The v3 example, from RFC 9562 appendix A.2
expect Uuid.v3(Uuid.namespace_dns, "www.example.com".to_utf8()) == parse("5df41881-3aed-3515-88a7-2f4a814cf09e")

expect Uuid.v3(Uuid.namespace_url, "".to_utf8()).version() == V3

# Nil and max
expect Uuid.nil.to_str() == "00000000-0000-0000-0000-000000000000"

expect Uuid.max.to_str() == "ffffffff-ffff-ffff-ffff-ffffffffffff"

expect Uuid.nil.version() == Other(0) and Uuid.max.version() == Other(15)

expect Uuid.nil.variant() == Ncs and Uuid.max.variant() == Future

# Variant boundaries in byte 8
expect
	[(0x00.U8, Ncs), (0x7F, Ncs), (0x80, Rfc9562), (0xBF, Rfc9562), (0xC0, Microsoft), (0xDF, Microsoft), (0xE0, Future), (0xFF, Future)].all(
		|(byte, variant)| Uuid.from_u128(byte.to_u128().shl_wrap(56)).variant() == variant,
	)

# Every version nibble
expect
	List.from_iter((0.U8).until(16)).all(
		|n| {
			v = Uuid.from_u128(n.to_u128().shl_wrap(76)).version()
			expected = match n {
				1 => V1
				2 => V2
				3 => V3
				4 => V4
				5 => V5
				6 => V6
				7 => V7
				8 => V8
				_ => Other(n)
			}
			v == expected
		},
	)

# v4, v7 and v8 always set their version and the RFC variant, and keep every
# other bit they're given
expect samples(500, 1).all(
	|bits| {
		a = Uuid.v4(bits)
		b = Uuid.v8(bits)
		c = Uuid.v7(bits.to_u64_wrap(), bits)
		keep = 0xFFFF_FFFF_FFFF_0FFF_3FFF_FFFF_FFFF_FFFF
		a.version() == V4 and a.variant() == Rfc9562 and a.to_u128().bitwise_and(keep) == bits.bitwise_and(keep)
			and b.version() == V8 and b.variant() == Rfc9562 and b.to_u128().bitwise_and(keep) == bits.bitwise_and(keep)
			and c.version() == V7 and c.variant() == Rfc9562 and c.unix_ms() == Ok(bits.to_u64_wrap().bitwise_and(0xFFFF_FFFF_FFFF))
	},
)

# Text, bytes and U128 round trip
expect samples(500, 2).all(
	|bits| {
		uuid = Uuid.from_u128(bits)
		Uuid.from_str(uuid.to_str()) == Ok(uuid)
			and Uuid.from_str_lenient(uuid.to_urn()) == Ok(uuid)
			and Uuid.from_bytes(uuid.to_bytes()) == Ok(uuid)
			and uuid.to_bytes().len() == 16
			and uuid.to_u128() == bits
	},
)

expect Uuid.from_bytes([1, 2, 3]) == Err(WrongLength(3))

expect parse("00112233-4455-6677-8899-aabbccddeeff").to_bytes() == [0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]

# Strict parsing reports what's wrong and where
expect Uuid.from_str("f81d4fae7dec11d0a76500a0c91e6bf6") == Err(InvalidUuid({ index: 8, problem: ExpectedHyphen }))

expect Uuid.from_str("f81d4fae-7dec-11d0-a765-00a0c91e6bfg") == Err(InvalidUuid({ index: 35, problem: InvalidChar('g') }))

expect Uuid.from_str("f81d4fae-7dec-11d0-a765-00a0c91e6bf") == Err(InvalidUuid({ index: 35, problem: WrongLength }))

expect Uuid.from_str("f81d4fae-7dec-11d0-a765-00a0c91e6bf60") == Err(InvalidUuid({ index: 36, problem: WrongLength }))

expect Uuid.from_str("") == Err(InvalidUuid({ index: 0, problem: WrongLength }))

expect Uuid.from_str("{f81d4fae-7dec-11d0-a765-00a0c91e6bf6}") == Err(InvalidUuid({ index: 0, problem: InvalidChar('{') }))

expect Uuid.from_str(" f81d4fae-7dec-11d0-a765-00a0c91e6bf6") == Err(InvalidUuid({ index: 0, problem: InvalidChar(' ') }))

# A bad byte at any position is reported there
expect {
	valid = "f81d4fae-7dec-11d0-a765-00a0c91e6bf6".to_utf8()
	List.from_iter((0.U64).until(36)).all(
		|position|
			['g', 'G', ' ', '-', 'x', '/', ':', '@', '`', '{'].all(
				|bad| {
					text = Str.from_utf8_lossy(valid.take_first(position).append(bad).concat(valid.drop_first(position + 1)))
					is_hyphen_slot = position == 8 or position == 13 or position == 18 or position == 23
					expected =
						if is_hyphen_slot {
							if (bad == '-') Ok(parse(text)) else Err(InvalidUuid({ index: position, problem: ExpectedHyphen }))
						} else {
							Err(InvalidUuid({ index: position, problem: InvalidChar(bad) }))
						}
					Uuid.from_str(text) == expected
				},
			),
	)
}

# Lenient parsing accepts the common spellings, in any case
expect {
	uuid = parse("f81d4fae-7dec-11d0-a765-00a0c91e6bf6")
	[
		"f81d4fae-7dec-11d0-a765-00a0c91e6bf6",
		"F81D4FAE-7DEC-11D0-A765-00A0C91E6BF6",
		"{f81d4fae-7dec-11d0-a765-00a0c91e6bf6}",
		"urn:uuid:f81d4fae-7dec-11d0-a765-00a0c91e6bf6",
		"URN:UUID:F81D4FAE-7DEC-11D0-A765-00A0C91E6BF6",
		"f81d4fae7dec11d0a76500a0c91e6bf6",
		"{f81d4fae7dec11d0a76500a0c91e6bf6}",
	].all(|text| Uuid.from_str_lenient(text) == Ok(uuid))
}

# ...and reports problems as offsets into the whole text
expect Uuid.from_str_lenient("{f81d4fae-7dec-11d0-a765-00a0c91e6bf6") == Err(InvalidUuid({ index: 37, problem: WrongLength }))

expect Uuid.from_str_lenient("urn:uuid:f81d4fae-7dec-11d0-a765-00a0c91e6bfx") == Err(InvalidUuid({ index: 44, problem: InvalidChar('x') }))

expect Uuid.from_str_lenient("urn:uuid:f81d4fae7dec11d0a76500a0c91e6bf6") == Err(InvalidUuid({ index: 17, problem: ExpectedHyphen }))

expect Uuid.from_str_lenient("f81d4fae7dec11d0a76500a0c91e6bf") == Err(InvalidUuid({ index: 31, problem: WrongLength }))

expect Uuid.from_str_lenient("f81d4fae7dec11d0a76500a0c91e6bfz") == Err(InvalidUuid({ index: 31, problem: InvalidChar('z') }))

expect Uuid.from_str_lenient("{}") == Err(InvalidUuid({ index: 1, problem: WrongLength }))

# Ordering is RFC byte order, and v7 sorts by time
expect Uuid.nil < Uuid.max and Uuid.max > Uuid.nil and Uuid.nil <= Uuid.nil and Uuid.max >= Uuid.max

expect Uuid.v7(1000, Uuid.max.to_u128()) < Uuid.v7(1001, 0)

# Uuid works as a Dict key
expect {
	a = parse("f81d4fae-7dec-11d0-a765-00a0c91e6bf6")
	b = Uuid.nil
	dict : Dict(Uuid, Str)
	dict = Dict.empty().insert(a, "a").insert(b, "b")
	dict.get(a) == Ok("a") and dict.get(b) == Ok("b") and dict.len() == 2
}

expect Str.inspect(Uuid.nil) == "Uuid(00000000-0000-0000-0000-000000000000)"

# v7_after: strictly increasing over random steps of the clock, including
# repeats and going backwards, and always a v7 with a sensible timestamp
expect {
	var $gen = gen(7)
	var $last = Uuid.nil
	var $ms = 1_700_000_000_000.U64
	var $ok = True
	for _ in List.from_iter((0.U64).until(3000)) {
		(r, after_r) = $gen.step()
		(bits, after_bits) = Uuid.random_bits(after_r)
		$gen = after_bits
		# Mostly the same millisecond, sometimes forward, sometimes backward
		$ms =
			match r % 10 {
				0 => $ms + r % 50
				1 => $ms - r % 20
				_ => $ms
			}
		next = Uuid.v7_after($last, $ms, bits)
		previous_ms = $last.unix_ms() ?? 0
		if !(next > $last and next.version() == V7 and next.variant() == Rfc9562 and (next.unix_ms() ?? 0) >= previous_ms) {
			$ok = False
			break
		}
		$last = next
	}
	$ok
}

# A new millisecond takes the new time; an earlier one keeps the last time
expect {
	first = Uuid.v7_after(Uuid.nil, 5000, 0)
	later = Uuid.v7_after(first, 6000, 0)
	earlier = Uuid.v7_after(later, 4000, 0)
	first.unix_ms() == Ok(5000) and later.unix_ms() == Ok(6000) and earlier.unix_ms() == Ok(6000) and earlier > later
}

# A fresh counter leaves room for 2048 more in the same millisecond
expect {
	start = Uuid.v7_after(Uuid.nil, 5000, Uuid.max.to_u128())
	start.to_u128().shr_zf_wrap(64).bitwise_and(0xFFF) == 0x7FF
}

# A full counter moves to the next millisecond
expect {
	full = Uuid.from_u128(Uuid.v7(5000, 0).to_u128().bitwise_or((0xFFF.U128).shl_wrap(64)))
	next = Uuid.v7_after(full, 5000, 0)
	next.unix_ms() == Ok(5001) and next > full
}
