app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	uuid: "../package/main.roc",
}

import pf.Monotonic
import pf.Stdout
import uuid.Uuid

## Times each operation over a batch of 10,000 UUIDs and prints nanoseconds
## per call, the fastest of 50 batches. Run with `just bench`.
main! = |_args| {
	ids = List.from_iter((0.U64).until(10_000)).map(|i| v4_of(i.to_u128().times_wrap(0x9E37_79B9_7F4A_7C15_F39C_C060_5CED_C835)))
	texts = ids.map(|id| id.to_str())
	name = "www.example.com".to_utf8()
	rows = [
		("from_str", best!(|{}| texts.fold(0, |n, t| n.plus_wrap((Uuid.from_str(t) ?? Uuid.nil).to_u128().to_u64_wrap())))),
		("from_str_lenient", best!(|{}| texts.fold(0, |n, t| n.plus_wrap((Uuid.from_str_lenient(t) ?? Uuid.nil).to_u128().to_u64_wrap())))),
		("to_str", best!(|{}| ids.fold(0, |n, id| n + id.to_str().count_utf8_bytes()))),
		("v4", best!(|{}| ids.fold(0, |n, id| n.plus_wrap(v4_of(id.to_u128()).to_u128().to_u64_wrap())))),
		("next_v7", best!(|{}| ids.fold(Uuid.nil, |last, id| next_v7_of(id.to_u128(), last)).to_u128().to_u64_wrap())),
		("v3", best!(|{}| ids.fold(0, |n, id| n.plus_wrap(Uuid.v3(id, name).to_u128().to_u64_wrap())))),
	]
	for (label, ns) in rows {
		Stdout.line!("${label}: ${(ns / 10_000).to_str()} ns")?
	}
	Ok({})
}

## The fastest of 50 runs of `f` over the batch, in nanoseconds. The result
## is used, so the work can't be skipped.
best! : ({} -> U64) => U64
best! = |f| {
	var $min = 0xFFFF_FFFF_FFFF_FFFF.U64
	var $sink = 0.U64
	for _ in List.from_iter((0.U64).until(52)) {
		start = Monotonic.now!()
		$sink = $sink.bitwise_xor(f({}))
		ns = start.elapsed!().to_nanos()
		if ns < $min {
			$min = ns
		}
	}
	if $sink == 1 {
		crash "unreachable, keeps the work"
	}
	$min
}

## A generator that hands out the two halves of `bits`, so a seeded `Gen`
## makes its UUID from exactly those bits
Fixed := [Fixed(U64, U64)].{
	step : Fixed -> (U64, Fixed)
	step = |Fixed(hi, lo)| (hi, Fixed(lo, 0))
}

fixed : U128 -> Uuid.Gen.Seeded(Fixed)
fixed = |bits| Uuid.Gen.Seeded.new(Fixed(bits.shr_zf_wrap(64).to_u64_wrap(), bits.to_u64_wrap()))

v4_of : U128 -> Uuid
v4_of = |bits| {
	(uuid, _) = fixed(bits).v4()
	uuid
}

next_v7_of : U128, Uuid -> Uuid
next_v7_of = |bits, last| {
	(uuid, _) = fixed(bits).next_v7(last, 1_700_000_000_000)
	uuid
}
