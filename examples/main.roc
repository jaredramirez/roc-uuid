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
	# Random UUIDs, with fresh random bits for each one
	Stdout.line!(Uuid.v4(Uuid.random_bits!(Random.seed_u64!)?).to_str())?
	now = Utc.now!().to_millis_since_epoch().to_u64_wrap()
	Stdout.line!(Uuid.v7(now, Uuid.random_bits!(Random.seed_u64!)?).to_str())?

	# A pure generator, seeded from the platform's randomness
	var $seed = Prng.seed(Random.seed_u64!()?)
	(bits, $seed) = Uuid.random_bits($seed)
	Stdout.line!(Uuid.v4(bits).to_str())?

	# Version 7 in order within a millisecond
	var $last = Uuid.nil
	for _ in List.from_iter((0.U64).until(3)) {
		$last = Uuid.v7_after($last, now, Uuid.random_bits!(Random.seed_u64!)?)
		Stdout.line!($last.to_str())?
	}

	# Name-based
	Stdout.line!(Uuid.v5(Uuid.namespace_dns, "www.example.com".to_utf8()).to_str())?
	Stdout.line!(Uuid.v3(Uuid.namespace_dns, "www.example.com".to_utf8()).to_str())?

	# Parsing, printing and the exposed types
	id = Uuid.from_str_lenient("{F81D4FAE-7DEC-11D0-A765-00A0C91E6BF6}")?
	Stdout.line!("${id.to_str()} ${id.to_urn()} ${describe(id.version())}")?
	Stdout.line!(Str.inspect(Uuid.from_str("f81d4fae7dec11d0a76500a0c91e6bf6")))?

	# Sorting
	sorted = [Uuid.max, Uuid.nil, id].sort()
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
