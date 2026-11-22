app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.7.0/HBigHQhVZWEF2EkLxpYK35u8P6UNsAmPYxpNFTxXK1Br.tar.zst",
	uuid: "../package/main.roc",
}

import fuzz.Fuzz
import uuid.Uuid

## Raw fuzz input: `data` is parsed as text and also supplies the bits for
## generating UUIDs, `previous` is the UUID `v7_after` follows, and `ms` is
## its clock reading
Input : { data : List(U8), previous : U128, ms : U64 }

## Parsing arbitrary text never misreports, generated UUIDs always have the
## right version, variant and timestamp, and `v7_after` always moves forward
test! : Input => Fuzz.Outcome
test! = |{ data, previous, ms }| {
	text = Str.from_utf8_lossy(data)
	bytes = text.to_utf8()

	# Strict parsing accepts only the canonical form, and errors point into
	# the text at the byte that's wrong
	match Uuid.from_str(text) {
		Ok(uuid) =>
			if uuid.to_str().to_utf8() != lowercase(bytes) {
				crash "from_str accepted something that isn't the canonical form"
			}
		Err(err) => check_error(err, bytes)
	}
	match Uuid.from_str_lenient(text) {
		Ok(uuid) =>
			if Uuid.from_str(uuid.to_str()) != Ok(uuid) {
				crash "a lenient parse did not survive a round trip"
			}
		Err(err) => check_error(err, bytes)
	}

	bits = data.take_first(16).fold(0.U128, |n, byte| n.shl_wrap(8).bitwise_or(byte.to_u128()))
	for (uuid, version) in [(Uuid.v4(bits), V4), (Uuid.v7(ms, bits), V7), (Uuid.v8(bits), V8)] {
		if uuid.version() != version or uuid.variant() != Rfc9562 or Uuid.from_bytes(uuid.to_bytes()) != Ok(uuid) {
			crash "a generated UUID has the wrong version, variant or bytes"
		}
	}
	if Uuid.v7(ms, bits).unix_ms() != Ok(ms.bitwise_and(0xFFFF_FFFF_FFFF)) {
		crash "v7 lost its timestamp"
	}

	# v7_after moves forward, except past the last millisecond in the year 10889
	before = Uuid.from_u128(previous)
	after = Uuid.v7_after(before, ms, bits)
	at_the_end = before.unix_ms() == Ok(0xFFFF_FFFF_FFFF) and previous.shr_zf_wrap(64).bitwise_and(0xFFF) == 0xFFF
	if after.version() != V7 or after.variant() != Rfc9562 {
		crash "v7_after made something other than a v7"
	}
	match before.unix_ms() {
		Ok(_) if !at_the_end and after <= before => crash "v7_after did not move forward"
		Err(NotV7) if after.unix_ms() != Ok(ms.bitwise_and(0xFFFF_FFFF_FFFF)) => crash "v7_after from a non-v7 ignored the clock"
		_ => {}
	}
	Fuzz.keep
}

check_error : [InvalidUuid({ index : U64, problem : [InvalidChar(U8), ExpectedHyphen, WrongLength] })], List(U8) => {}
check_error = |InvalidUuid({ index, problem }), bytes|
	match problem {
		InvalidChar(byte) if bytes.get(index) == Ok(byte) => {}
		InvalidChar(_) => crash "InvalidChar points at the wrong byte"
		ExpectedHyphen if bytes.get(index) != Ok('-') => {}
		ExpectedHyphen => crash "ExpectedHyphen points at a hyphen"
		WrongLength if index <= bytes.len() => {}
		WrongLength => crash "WrongLength points past the end"
	}

lowercase : List(U8) -> List(U8)
lowercase = |bytes| bytes.map(|c| if (c >= 'A' and c <= 'Z') c + 32 else c)

target = Fuzz.target_with!({
	examples: [
		Fuzz.example({ name: "empty", revision: "1", make: || { data: [], previous: 0, ms: 0 } }),
		Fuzz.example({ name: "canonical", revision: "1", make: || { data: "f81d4fae-7dec-11d0-a765-00a0c91e6bf6".to_utf8(), previous: 0, ms: 1 } }),
		Fuzz.example({ name: "urn", revision: "1", make: || { data: "urn:uuid:017f22e2-79b0-7cc3-98c4-dc0c0c07398f".to_utf8(), previous: 0x017F_22E2_79B0_7CC3_98C4_DC0C_0C07_398F, ms: 0x017F_22E2_79B0 } }),
		Fuzz.example({ name: "full-counter", revision: "1", make: || { data: "{f81d4fae7dec11d0a76500a0c91e6bf6}".to_utf8(), previous: 0x017F_22E2_79B0_7FFF_98C4_DC0C_0C07_398F, ms: 0 } }),
	],
	name: "uuid",
	generator: Fuzz.map2(
		Fuzz.map2(Fuzz.bytes, Fuzz.u64, |data, ms| (data, ms)),
		Fuzz.map2(Fuzz.u64, Fuzz.u64, |hi, lo| hi.to_u128().shl_wrap(64).bitwise_or(lo.to_u128())),
		|(data, ms), previous| { data, previous, ms },
	),
	test!,
	show: |input| Str.inspect(input),
})
