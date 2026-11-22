set positional-arguments

# List available commands.
default:
    @just --list

check:
    roc check package/main.roc
    roc check fuzz/main.roc
    roc check bench/main.roc
    roc check diff/oracle.roc

test:
    roc test package/main.roc

# Run the tests with every backend: the interpreter, dev, size, and speed.
test-all:
    for opt in interpreter dev size speed; do roc test --opt=$opt package/main.roc || exit 1; done

fmt:
    roc fmt package fuzz bench diff

# Fail if any file needs formatting.
fmt-check:
    roc fmt --check package fuzz bench diff

docs:
    roc docs package/main.roc --output=generated-docs

# Check the fuzz examples, then explore for the given number of seconds.
fuzz seconds="30":
    mkdir -p fuzz-out/corpus
    roc build --fuzz fuzz/main.roc --output=fuzz-out/uuid
    cd fuzz-out && ./uuid check && ./uuid explore corpus --time={{seconds}}

# Compare against Python's uuid module on random inputs. See --help.
diff *args:
    mkdir -p diff-out
    roc build --opt=speed diff/oracle.roc --output=diff-out/oracle
    python3 -I diff/diff.py diff-out/oracle "$@"

# Time parsing, formatting, and generating, in nanoseconds per call.
bench:
    mkdir -p bench-out
    roc build --opt=speed bench/main.roc --output=bench-out/bench
    ./bench-out/bench

bundle:
    rm -rf dist && mkdir -p dist
    cp LICENSE package/LICENSE
    cd package && roc bundle main.roc Uuid.roc LICENSE --output-dir ../dist; status=$?; rm -f LICENSE; exit $status
