//! Times the same work as bench/main.roc with the uuid crate and prints
//! `operation: NS` lines, the fastest nanoseconds per call.

use std::hint::black_box;
use std::time::Instant;
use uuid::{Builder, Uuid};

const COUNT: u128 = 10_000;
const MS: u64 = 1_700_000_000_000;

/// The fastest of 50 batches, in nanoseconds per call
fn best(f: impl Fn() -> u64) -> f64 {
    let mut min = u64::MAX;
    let mut sink = 0;
    for _ in 0..52 {
        let start = Instant::now();
        sink ^= black_box(f());
        min = min.min(start.elapsed().as_nanos() as u64);
    }
    black_box(sink);
    min as f64 / COUNT as f64
}

fn low(id: Uuid) -> u64 {
    id.as_u128() as u64
}

fn main() {
    let ids: Vec<Uuid> = (0..COUNT)
        .map(|i| Builder::from_random_bytes(i.wrapping_mul(0x9E37_79B9_7F4A_7C15_F39C_C060_5CED_C835).to_be_bytes()).into_uuid())
        .collect();
    let texts: Vec<String> = ids.iter().map(|id| id.to_string()).collect();
    let name = b"www.example.com";
    let rows: [(&str, f64); 7] = [
        ("from_str", best(|| texts.iter().fold(0, |n, t| n.wrapping_add(low(Uuid::parse_str(black_box(t)).unwrap_or(Uuid::nil())))))),
        ("to_str", best(|| ids.iter().fold(0, |n, id| n + black_box(id).to_string().len() as u64))),
        ("v4", best(|| ids.iter().fold(0, |n, id| n.wrapping_add(low(Builder::from_random_bytes(*black_box(id.as_bytes())).into_uuid()))))),
        ("v7", best(|| ids.iter().fold(0, |n, id| {
            let random: [u8; 10] = black_box(id.as_bytes())[6..].try_into().unwrap();
            n.wrapping_add(low(Builder::from_unix_timestamp_millis(MS, &random).into_uuid()))
        }))),
        ("v8", best(|| ids.iter().fold(0, |n, id| n.wrapping_add(low(Builder::from_custom_bytes(*black_box(id.as_bytes())).into_uuid()))))),
        ("v5", best(|| ids.iter().fold(0, |n, id| n.wrapping_add(low(Uuid::new_v5(black_box(id), name)))))),
        ("v3", best(|| ids.iter().fold(0, |n, id| n.wrapping_add(low(Uuid::new_v3(black_box(id), name)))))),
    ];
    for (label, ns) in rows {
        println!("{label}: {ns:.1}");
    }
}
