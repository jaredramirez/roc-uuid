// Times the same work as bench/main.roc with github.com/google/uuid and
// prints `operation: NS` lines, the fastest nanoseconds per call. The
// library has no version 7 or 8 from given bits, so those are left out.
package main

import (
	"bytes"
	"fmt"
	"math/big"
	"time"

	"github.com/google/uuid"
)

const count = 10_000

// Written after every batch, so the work can't be skipped
var sink uint64

// The fastest of 50 batches, in nanoseconds per call
func best(f func() uint64) float64 {
	min := uint64(1<<64 - 1)
	for i := 0; i < 52; i++ {
		start := time.Now()
		sink ^= f()
		if ns := uint64(time.Since(start).Nanoseconds()); ns < min {
			min = ns
		}
	}
	return float64(min) / count
}

func low(id uuid.UUID) uint64 {
	var n uint64
	for _, b := range id[8:] {
		n = n<<8 | uint64(b)
	}
	return n
}

func main() {
	mul, _ := new(big.Int).SetString("9E3779B97F4A7C15F39CC0605CEDC835", 16)
	mod := new(big.Int).Lsh(big.NewInt(1), 128)
	ids := make([]uuid.UUID, count)
	for i := range ids {
		var raw [16]byte
		new(big.Int).Mod(new(big.Int).Mul(big.NewInt(int64(i)), mul), mod).FillBytes(raw[:])
		ids[i], _ = uuid.NewRandomFromReader(bytes.NewReader(raw[:]))
	}
	texts := make([]string, count)
	for i, id := range ids {
		texts[i] = id.String()
	}
	name := []byte("www.example.com")
	rows := []struct {
		label string
		ns    float64
	}{
		{"from_str", best(func() uint64 {
			var n uint64
			for _, t := range texts {
				id, _ := uuid.Parse(t)
				n += low(id)
			}
			return n
		})},
		{"to_str", best(func() uint64 {
			var n uint64
			for _, id := range ids {
				n += uint64(len(id.String()))
			}
			return n
		})},
		{"v4", best(func() uint64 {
			var n uint64
			reader := bytes.NewReader(nil)
			for _, id := range ids {
				reader.Reset(id[:])
				made, _ := uuid.NewRandomFromReader(reader)
				n += low(made)
			}
			return n
		})},
		{"v5", best(func() uint64 {
			var n uint64
			for _, id := range ids {
				n += low(uuid.NewSHA1(id, name))
			}
			return n
		})},
		{"v3", best(func() uint64 {
			var n uint64
			for _, id := range ids {
				n += low(uuid.NewMD5(id, name))
			}
			return n
		})},
	}
	for _, row := range rows {
		fmt.Printf("%s: %.1f\n", row.label, row.ns)
	}
}
