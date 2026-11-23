app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	prng: "https://github.com/niclas-ahden/roc-prng/releases/download/0.4.1/C3JpBYoPwC9SN5aweoh1Dux2K3iy4vfMTdAsWooE1HF5.tar.zst",
	uuid: "../package/main.roc",
}

import pf.Random
import pf.Stdout
import pf.Utc
import prng.Random as Prng
import uuid.Uuid

## Every example from the README, so CI checks that they compile and run
main! = |_args| {
	# Version 4: random
	bits = Uuid.random_bits!(Random.seed_u64!)?
	id = Uuid.v4(bits)
	Stdout.line!("v4: ${id.to_str()}")?

	# Version 7: random, but sorted by time
	now = Utc.now!().to_millis_since_epoch().to_u64_wrap()
	more_bits = Uuid.random_bits!(Random.seed_u64!)?
	sorted_id = Uuid.v7(now, more_bits)
	Stdout.line!("v7: ${sorted_id.to_str()}")?

	# A pure generator, seeded from the platform's randomness
	var $seed = Prng.seed(Random.seed_u64!()?)
	(seeded_bits, $seed) = Uuid.random_bits($seed)
	seeded_id = Uuid.v4(seeded_bits)
	Stdout.line!("seeded v4: ${seeded_id.to_str()}")?

	# Version 7 in order within a millisecond
	var $last = Uuid.nil
	for _ in List.from_iter((0.U64).until(3)) {
		row_bits = Uuid.random_bits!(Random.seed_u64!)?
		$last = $last.v7_after(now, row_bits)
		Stdout.line!($last.to_str())?
	}

	# Name-based
	by_name = Uuid.v5(Uuid.namespace_dns, "www.example.com".to_utf8())
	Stdout.line!("v5: ${by_name.to_str()}")?
	by_name_md5 = Uuid.v3(Uuid.namespace_dns, "www.example.com".to_utf8())
	Stdout.line!("v3: ${by_name_md5.to_str()}")?

	# Parsing, printing and the exposed types
	parsed = Uuid.from_str_lenient("{F81D4FAE-7DEC-11D0-A765-00A0C91E6BF6}")?
	Stdout.line!("${parsed.to_str()} ${parsed.to_urn()} ${describe(parsed.version())}")?
	Stdout.line!(Str.inspect(Uuid.from_str("f81d4fae7dec11d0a76500a0c91e6bf6")))?

	# Sorting
	sorted = [Uuid.max, Uuid.nil, parsed].sort()
	Stdout.line!(sorted.map(|u| u.to_str()) |> Str.join_with(" < "))?
	Ok({})
}

describe : Uuid.Version -> Str
describe = |version|
	match version {
		V4 => "random"
		V7 => "time-ordered"
		V1 | V6 => "time-based"
		V3 | V5 => "name-based"
		_ => "other"
	}
