app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	uuid: "../package/main.roc",
}

import pf.Random
import pf.Stdin
import pf.Stdout
import uuid.Uuid

## The Roc side of `just diff`: diff/diff.py writes one case per line to
## stdin, this answers each with one line, and diff.py checks every answer
## against Python's uuid module. Numbers and bytes travel as hexadecimal.
##
## - `B <bits> <ms>`: the UUID with those bits, as text, URN, bytes, version
##   and variant, then `v4`, `v7` and `v8` made from the same bits
## - `N3 <namespace> <name>`, `N5 <namespace> <name>`: `v3` or `v5` of a
##   name in a namespace
## - `P <text>`: `from_str` and `from_str_lenient` of the text
## - `A <previous> <ms> <bits>`: `v7_after`
## - `NS`: the four namespaces
## - `R`: a `v4` from `random_bits!` with the platform's randomness
main! = |_args| {
	input = Stdin.read_to_end!()?
	var $out = []
	for line in Str.from_utf8_lossy(input).split_on("\n") {
		if line != "" {
			$out = $out.append(answer!(line.split_on(" ")))
		}
	}
	Stdout.write!(Str.join_with($out, "\n").concat("\n"))?
	Ok({})
}

answer! : List(Str) => Str
answer! = |words|
	match words {
		["B", bits_hex, ms_hex] => {
			bits = hex_u128(bits_hex)
			ms = hex_u128(ms_hex).to_u64_wrap()
			uuid = Uuid.from_u128(bits)
			[
				uuid.to_str(),
				uuid.to_urn(),
				hex_bytes(uuid.to_bytes()),
				version_str(uuid.version()),
				variant_str(uuid.variant()),
				Uuid.v4(bits).to_str(),
				Uuid.v7(ms, bits).to_str(),
				Uuid.v8(bits).to_str(),
			]
				|> Str.join_with(" ")
		}
		["N3", namespace_hex, name_hex] => Uuid.v3(Uuid.from_u128(hex_u128(namespace_hex)), unhex(name_hex)).to_str()
		["N3", namespace_hex] => Uuid.v3(Uuid.from_u128(hex_u128(namespace_hex)), []).to_str()
		["N5", namespace_hex, name_hex] => Uuid.v5(Uuid.from_u128(hex_u128(namespace_hex)), unhex(name_hex)).to_str()
		["N5", namespace_hex] => Uuid.v5(Uuid.from_u128(hex_u128(namespace_hex)), []).to_str()
		["P", text_hex] => {
			text = Str.from_utf8_lossy(unhex(text_hex))
			"${result_str(Uuid.from_str(text))} ${result_str(Uuid.from_str_lenient(text))}"
		}
		["P"] => "${result_str(Uuid.from_str(""))} ${result_str(Uuid.from_str_lenient(""))}"
		["A", previous_hex, ms_hex, bits_hex] => Uuid.v7_after(Uuid.from_u128(hex_u128(previous_hex)), hex_u128(ms_hex).to_u64_wrap(), hex_u128(bits_hex)).to_str()
		["NS"] => [Uuid.namespace_dns, Uuid.namespace_url, Uuid.namespace_oid, Uuid.namespace_x500].map(|u| u.to_str()) |> Str.join_with(" ")
		["R"] =>
			match Uuid.random_bits!(Random.seed_u64!) {
				Ok(bits) => Uuid.v4(bits).to_str()
				Err(_) => "random-error"
			}
		_ => "bad-case"
	}

result_str : Try(Uuid, _) -> Str
result_str = |result|
	match result {
		Ok(uuid) => "ok:${uuid.to_str()}"
		Err(InvalidUuid({ index, problem })) => {
			name = match problem {
				InvalidChar(_) => "char"
				ExpectedHyphen => "hyphen"
				WrongLength => "length"
			}
			"err:${index.to_str()}:${name}"
		}
	}

version_str : _ -> Str
version_str = |version|
	match version {
		V1 => "1"
		V2 => "2"
		V3 => "3"
		V4 => "4"
		V5 => "5"
		V6 => "6"
		V7 => "7"
		V8 => "8"
		Other(n) => n.to_str()
	}

variant_str : _ -> Str
variant_str = |variant|
	match variant {
		Ncs => "ncs"
		Rfc9562 => "rfc"
		Microsoft => "microsoft"
		Future => "future"
	}

nibble : U8 -> U8
nibble = |c| if (c >= 'a') c - 'a' + 10 else if (c >= 'A') c - 'A' + 10 else c - '0'

hex_u128 : Str -> U128
hex_u128 = |text| text.to_utf8().fold(0, |n, c| n.shl_wrap(4).bitwise_or(nibble(c).to_u128()))

unhex : Str -> List(U8)
unhex = |text|
	text.to_utf8().chunks_of(2).map(
		|pair|
			match pair {
				[hi, lo] => nibble(hi).shl_wrap(4).bitwise_or(nibble(lo))
				_ => crash "hex comes in pairs"
			},
	)

hex_bytes : List(U8) -> Str
hex_bytes = |bytes| {
	digit = |n| if (n < 10) '0' + n else 'a' + n - 10
	Str.from_utf8_lossy(bytes.fold([], |out, b| out.append(digit(b.shr_zf_wrap(4))).append(digit(b.bitwise_and(0xF)))))
}
