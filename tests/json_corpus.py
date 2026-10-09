"""Independent Python oracle for JSON decoding and full writer reconstruction."""
import json
import random
import subprocess
import sys
import tempfile
from pathlib import Path

rng = random.Random(8259)

def value(depth=0):
    if depth < 4:
        choice = rng.randrange(7)
        if choice == 0:
            return [value(depth + 1) for _ in range(rng.randrange(6))]
        if choice == 1:
            return {f"k{i} café 🚀": value(depth + 1) for i in range(rng.randrange(6))}
    return rng.choice([None, True, False, rng.randrange(-10**25, 10**25),
                       rng.uniform(-1e20, 1e20), 'quote"\\\n\t\x00 café 日本語 🚀'])

valid = [b"null", b"true", b"false", b"-0", b"1e400", b"1e-400",
         b"9223372036854775808", b"-9223372036854775809", b"[]", b"{}",
         b' {"a":1,"a":2,"\\u0061":3} ', b'"\\u0000\\b\\f\\n\\r\\t\\/"',
         b'"\\uDBFF\\uDFFF"', b"[" * 128 + b"0" + b"]" * 128]
for _ in range(80):
    obj = value()
    for ascii_only in (True, False):
        valid.append(json.dumps(obj, ensure_ascii=ascii_only).encode("utf-8"))
invalid = [b"", b" ", b"[", b"{", b"[1,]", b'{"a":1,}', b'{"a" 1}',
           b"[1 2]", b"truefalse", b"null 0", b"00", b"-01", b"+1", b".1",
           b"1.", b"1e", b"1e+", b"NaN", b"Infinity", b"\xef\xbb\xbfnull",
           b'"\n"', b'"\\x20"', b'"\\u12"', b'"\\uZZZZ"', b'"\\uD800"',
           b'"\\uDC00"', b'"\\uD800\\u0041"', b'"\x80"', b'"\xc0\xaf"',
           b'"\xed\xa0\x80"', b'"\xf4\x90\x80\x80"', b'"\xe2\x82"',
           b"[" * 129 + b"0" + b"]" * 129, b"[0]\v", b"[0]\f"]
with tempfile.TemporaryDirectory(prefix="goose-json-") as temp:
    path = Path(temp) / "input.json"
    for data in valid + invalid:
        path.write_bytes(data)
        result = subprocess.run([sys.argv[1], str(path)], capture_output=True, timeout=10)
        assert result.returncode == 0, (data[:100], result.stderr)
        output = result.stdout.decode("utf-8").replace("\r\n", "\n")
        if data in invalid:
            assert output.startswith("ERROR "), (data, output)
        else:
            assert output.startswith("OK\n"), (data[:100], output)
            assert json.loads(output[3:]) == json.loads(data), (data[:100], output)
print(f"JSON independent round trips: {len(valid)} valid, {len(invalid)} invalid")
