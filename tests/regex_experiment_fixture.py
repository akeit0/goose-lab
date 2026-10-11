"""Compare stdlib regex search/captures/replacement with independent Python bytes RE."""
import re
import subprocess
import sys

INVALID_PATTERNS = (b"[", b"(a", b"a{1001}", b"^a", b"a$", rb"\bword")

def batches():
    patterns = [b"", b"a", b"ab|a", b"a|ab", b"a*", b"a?", b"(a|)", b"(a+)(b?)", b"(ab)+", b"(a)?b",
                b"(a|b)+", b"a+?", b"a.*b", b"a.*?b", b"[a-c]+", b"[^a-c]+", b"[0-9]{1,3}",
                rb"(\w+)=(\d+)", rb"\s+", rb"\x00+", b"(?i)(ab)+", b"(?s)a.b", b"(a(b|c)){1,3}",
                rb"(\w+)@(\w+)\.com", b"a*ab|a*c?"]
    patterns += [f"({left})(?:{right}){{1,3}}".encode() for left in ("a", "[ab]", "a|b") for right in ("b", "[bc]", "c?")]
    texts = [b"", b"a", b"b", b"ab", b"aaa", b"aab", b"abab", b"abba", b"abbbbc", b"abcabc",
             b"a\nb", b"AbaB", b"x=123 y=7", b"foo@bar.com no@x.com", b"\x00\x00a", "日a🙂b".encode()]
    seed = 238147
    for _ in range(32):
        data = bytearray()
        for _ in range(48):
            seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF
            data.append(b"abccxyzABC0129_ =@.\n\x00"[(seed >> 16) % 20])
        texts.append(bytes(data))
    for pattern in patterns: yield pattern, texts
    for pattern in INVALID_PATTERNS:
        yield pattern, [b"", b"abc"]
    yield b"(a+)", [b"aaa", b"b"]  # Successful compilation after recoverable errors.


def matches(pattern, text):
    # Python determines each match and captures. Adapt only the documented Goose
    # iteration policy: no empty match at the preceding match's end.
    cursor, previous_end = 0, -1
    while cursor <= len(text):
        match = pattern.search(text, cursor)
        if match is None: return
        if match.start() == match.end() == previous_end:
            if cursor == len(text): return
            cursor += 1
            continue
        yield match
        cursor, previous_end = match.end(), match.end()


def input_and_expected():
    payload, rows = [], []
    cases = captures = 0
    all_batches = list(batches())
    for batch, (pattern, texts) in enumerate(all_batches):
        payload.append(pattern.hex() + "\t" + str(len(texts)))
        invalid = pattern in INVALID_PATTERNS
        compiled = None if invalid else re.compile(pattern)
        rows.append(f"invalid,{batch}" if invalid else f"compiled,{batch},{compiled.groups+1}")
        retained = None
        for case, text in enumerate(texts):
            payload.append(text.hex()); cases += 1
            found = [] if invalid else list(matches(compiled, text))
            start, end = found[0].span() if found else (-1, -1)
            rows.append(f"case,{batch},{case},{start},{end},{len(found)},{int(bool(found))}")
            replaced = bytearray(); cursor = 0
            for number, match in enumerate(found):
                spans = [offset for group in range(compiled.groups+1) for offset in match.span(group)]
                groups = [(match.group(group) or b"").hex() for group in range(compiled.groups+1)]
                rows.append(",".join(map(str, ("capture", batch, case, number, *spans, *groups)))); captures += 1
                if retained is None: retained = match.group()
                replaced += text[cursor:match.start()] + b"<" + match.group() + b">"; cursor = match.end()
            replaced += text[cursor:]
            rows.append(f"replaced,{batch},{case},{replaced.hex()}")
            rows.append(f"retained,{batch},{case},{(retained or b'').hex()}")
    rows.append(f"Regex experiment passed,{len(all_batches)}")
    return "\n".join(payload) + "\n", rows, {"patterns": len(all_batches), "cases": cases, "captures": captures}


def validate(stdout):
    _, wanted, metrics = input_and_expected(); actual = stdout.splitlines()
    if actual != wanted:
        index = next((i for i, pair in enumerate(zip(actual, wanted)) if pair[0] != pair[1]), min(len(actual), len(wanted)))
        raise AssertionError(f"Regex differs at {index}: {actual[index:index+1]} expected {wanted[index:index+1]}")
    return dict(metrics, rows=len(actual))


def run(binary):
    payload, _, _ = input_and_expected()
    process = subprocess.run([str(binary)], input=payload, capture_output=True, text=True, encoding="utf-8", timeout=120)
    if process.returncode:
        print(process.stdout[-2000:]); print(process.stderr, file=sys.stderr); process.check_returncode()
    metrics = validate(process.stdout)
    for damaged in (process.stdout.replace("capture,0,0,0,0,0", "capture,0,0,0,0,1", 1), "\n".join(process.stdout.splitlines()[:-1])):
        try: validate(damaged)
        except AssertionError: pass
        else: raise AssertionError("Regex oracle accepted a damaged trace")
    print(f"Regex experiment: {metrics}")
    return process, metrics


if __name__ == "__main__":
    run(sys.argv[1])
