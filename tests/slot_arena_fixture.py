"""Validate variable-value slots against independent flat Python byte arrays."""
import csv
import subprocess
import sys


def expected():
    rows = []
    for count in (3, 16, 64):
        for initial in (238147, 3984127, 4294967294):
            values = [b""] * count
            seed = initial
            written = refused = 0
            for step in range(3000):
                seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF
                slot, choice = (seed >> 8) % count, (seed >> 24) % 10
                if choice < 7:
                    size = (seed >> 16) % 257
                    if sum(map(len, values)) - len(values[slot]) + size > count * 73:
                        refused += 1
                    else:
                        values[slot] = bytes((step + slot * 31 + n * 17) % 256 for n in range(size))
                        written += size
                elif choice < 9:
                    values[slot] = b""
                if (step + 1) % 100 == 0:
                    checksum = sum((i + 1) * (n + 1) * byte for i, value in enumerate(values) for n, byte in enumerate(value))
                    rows.append((count, initial, step + 1, sum(map(len, values)), written, refused, checksum))
    return rows


def validate(stdout):
    rows = []
    summaries = []
    for row in csv.reader(stdout.splitlines()):
        if row[0] == "arena":
            rows.append(tuple(map(int, row[1:])))
        else:
            summaries.append(",".join(row))
    if rows != expected() or summaries != ["slot arena boundaries and ownership passed",
                                          "slot arena maximum: 4194304 bytes, 64 reuse cycles passed", "Slot arena contracts passed"]:
        raise AssertionError("Slot arena differs from independent flat-byte model or coverage is incomplete")
    return {"operations": 27000, "checkpoints": len(rows), "refusals": sum(r[5] for r in rows if r[2] == 3000)}


def run(binary, prefix=None):
    result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=60)
    if prefix:
        prefix.with_suffix(".stdout").write_text(result.stdout, encoding="utf-8")
        prefix.with_suffix(".stderr").write_text(result.stderr, encoding="utf-8")
    if result.returncode:
        print(result.stdout[-3000:]); print(result.stderr, file=sys.stderr); result.check_returncode()
    model = validate(result.stdout)
    rows = result.stdout.splitlines()
    for index, row in enumerate(rows):
        if row.startswith("arena,"):
            fields = row.split(","); fields[-1] = str(int(fields[-1]) + 1); rows[index] = ",".join(fields); break
    for corrupted in ("\n".join(result.stdout.splitlines()[:-1]), result.stdout.replace("arena,3,", "arena,16,", 1), "\n".join(rows)):
        try:
            validate(corrupted)
        except AssertionError:
            continue
        raise AssertionError("Slot arena oracle accepted corrupted trace")
    print(f"Slot arena oracle passed: {model}")
    return result, model


if __name__ == "__main__":
    run(sys.argv[1])
