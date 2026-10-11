"""Independent document/request model, flat-file search oracle and HTTP barriers."""
from collections import Counter
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading

from http_clients_fixture import Handler, Server

TEXT = "".join(f"A:{i:03} needle payload\r\n" for i in range(96)).encode()


def expected_trace():
    trace, paths = [], []
    generations, http_serial, search_serial = [0] * 3, [0] * 3, [0] * 3
    prior, rejected, applied, hit_count = None, 0, 0, 0
    for round_number in range(3):
        trace.append(f"round,{round_number}")
        documents, latest, requests, delivered = {}, {}, {}, set()
        next_key = 0
        for slot in range(3):
            generations[slot] += 1
            text = f"doc-{round_number}-{slot}"
            documents[slot] = {"generation": generations[slot], "revision": 1, "text": text, "base": text, "selection": (3, 1)}
            trace.append(f"open,{slot},{generations[slot]},{text}")
        trace.extend(f"pending-slot,{lane},{lane+7}" for lane in range(6))
        trace.append("pending-capacity,6,6,12,0")

        def request(label, slot, kind):
            nonlocal next_key
            next_key += 1
            d = documents[slot]
            item = {"label": label, "slot": slot, "generation": d["generation"], "revision": d["revision"], "key": next_key, "kind": kind}
            requests[label] = item; latest[slot, kind] = item
            trace.append(f"request,{label},{slot},{d['generation']},{d['revision']},{next_key},{kind}")
            return item

        def start(label):
            item = requests[label]; serials = http_serial if item["kind"] == 0 else search_serial
            serials[item["slot"]] += 1; item["serial"] = serials[item["slot"]]
            if item["kind"] == 0:
                paths.append(f"/{'hold' if label in ('active-old', 'close-old') else 'value'}/{label}-{round_number}")

        def current(item):
            d = documents.get(item["slot"]); wanted = latest.get((item["slot"], item["kind"]))
            return bool(d and wanted and (item["generation"], item["revision"], item["key"]) ==
                        (d["generation"], d["revision"], wanted["key"]))

        def http(label, item=None, cancelled=False):
            nonlocal rejected, applied
            item = item or requests[label]
            identity = (item["slot"], item["generation"], item["revision"], item["key"], "http")
            accepted = int(current(item) and identity not in delivered)
            if accepted: delivered.add(identity)
            applied += accepted; rejected += 1 - accepted
            prefix = f"http,{label},{item['slot']},{item['generation']},{item['revision']},{item['key']},{item['serial']}"
            if cancelled:
                trace.append((prefix + ",7,", ",,0"))  # A raced native status may be 0 or 200.
                assert not accepted
            else:
                trace.append(prefix + f",0,200,{item['label']}-{item.get('round', round_number)},{accepted}")

        def page(label, source=None, sequence=1, done=False, cancelled=False, first=0, count=0):
            nonlocal rejected, applied, hit_count
            item = requests[source or label]
            identity = (item["slot"], item["generation"], item["revision"], item["key"], sequence)
            accepted = int(current(item) and identity not in delivered)
            if accepted: delivered.add(identity)
            applied += accepted; rejected += 1 - accepted
            trace.append(f"page,{label},{item['slot']},{item['generation']},{item['revision']},{item['key']},{item['serial']},{sequence},{int(done)},{7 if cancelled else 0},{count},{accepted}")
            offset = sum(len(raw) for raw in TEXT.splitlines(keepends=True)[:first])
            for number, raw in enumerate(TEXT.splitlines(keepends=True)[first:first+count], first + 1):
                start_at = raw.index(b"needle")
                trace.append(f"hit,{label},data.txt,{number},{start_at+1},{offset+start_at},{offset+start_at+6},{raw.rstrip().decode()}")
                offset += len(raw); hit_count += 1

        def edit(text):
            d = documents[2]; d["text"] += text; d["revision"] += 1; d["selection"] = (len(d["text"]),) * 2
            trace.append(f"edit,2,{text}")

        request("epoch", 0, 0); start("epoch")
        if prior is not None: http("prior-controller", prior)
        http("epoch"); prior = dict(requests["epoch"], round=round_number)
        request("pending-old", 0, 0); request("pending-new", 0, 0)
        request("query-old", 1, 1); request("query-new", 1, 1)
        request("revision-pending", 2, 0); edit("!"); trace.append("blocked,2,0,0")
        start("pending-new"); start("query-new"); http("pending-new"); page("query-new", done=True)
        request("active-old", 0, 0); start("active-old")
        request("active-new", 0, 0); request("live", 2, 0); start("live"); trace.append("retained,active,62")
        http("live"); http("active-old", cancelled=True); start("active-new"); http("active-new")
        request("delayed", 1, 0); start("delayed"); request("delayed-new", 1, 0)
        http("delayed"); start("delayed-new"); http("delayed-new")
        request("revision-active", 2, 0); start("revision-active"); edit("+"); http("revision-active")
        request("held-old", 0, 1); start("held-old"); page("held-old", count=32)
        page("held-duplicate", "held-old", count=32)
        request("held-new", 0, 1); request("while-held", 2, 0); start("while-held"); http("while-held")
        page("held-old", done=True, cancelled=True); trace.append("ack,held-old,3")
        start("held-new"); page("held-new", done=True)
        request("close-old", 1, 0); request("close-search", 1, 1); start("close-old"); start("close-search")
        page("close-search", count=32); request("close-queued", 1, 0); request("close-query-queued", 1, 1)
        trace.append(f"close,1,{generations[1]}"); documents.pop(1)
        latest.pop((1, 0)); latest.pop((1, 1)); generations[1] += 1
        text = f"reopened-{round_number}"
        documents[1] = {"generation": generations[1], "revision": 1, "text": text, "base": text, "selection": (0, 0)}
        trace.append(f"open,1,{generations[1]},{text}")
        request("reopened", 1, 0); request("reopened-search", 1, 1); trace.append("retained,closed,62")
        http("close-old", cancelled=True); page("close-search", done=True, cancelled=True); trace.append("ack,close-search,3")
        start("reopened"); start("reopened-search"); http("reopened"); http("reopened-duplicate", requests["reopened"])
        for sequence in range(1, 4): page("reopened-search", sequence=sequence, first=(sequence-1)*32, count=32)
        page("reopened-search", sequence=4, done=True)
        for slot, d in sorted(documents.items()):
            trace.append(f"document,{slot},{d['generation']},{d['revision']},{int(d['text'] != d['base'])},{d['selection'][0]},{d['selection'][1]},{d['text']},{d['base']}")
        trace.append("clean,16,16,2,1")
    trace.append("Document service contracts passed")
    return trace, Counter(paths), {"rounds": 3, "http_requests": sum(http_serial), "search_requests": sum(search_serial),
                                  "exported_search_hits": hit_count, "applied_completions": applied, "rejected_completions": rejected}


def validate(stdout):
    expected, _, metrics = expected_trace(); actual = stdout.splitlines()
    if len(actual) != len(expected):
        raise AssertionError(f"Incomplete document/request trace: {len(actual)} expected {len(expected)}")
    for number, (row, wanted) in enumerate(zip(actual, expected)):
        if isinstance(wanted, tuple):
            prefix, suffix = wanted
            valid = row.startswith(prefix) and row.endswith(suffix) and row[len(prefix):-len(suffix)] in ("0", "200")
        else:
            valid = row == wanted
        if not valid:
            raise AssertionError(f"Document/request model mismatch at {number}: {row} expected {wanted}")
    return dict(metrics, rows=len(actual))


def run(binary):
    Handler.barriers = {}; observed = []

    class RecordedHandler(Handler):
        def do_GET(self):
            if not self.path.startswith(("/ready/", "/release/")):
                with self.lock: observed.append(self.path)
            super().do_GET()

    server = Server(("127.0.0.1", 0), RecordedHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
    env = dict(os.environ, NO_PROXY="127.0.0.1,localhost", no_proxy="127.0.0.1,localhost")
    try:
        with tempfile.TemporaryDirectory(prefix="goose-doc-services-") as directory:
            (Path(directory) / "data.txt").write_bytes(TEXT)
            process = subprocess.run([str(binary), f"http://127.0.0.1:{server.server_port}", directory],
                                     capture_output=True, text=True, encoding="utf-8", env=env, timeout=60)
        if process.returncode:
            print(process.stdout, end=""); print(process.stderr, file=sys.stderr, end=""); process.check_returncode()
        metrics = validate(process.stdout)
        _, expected_paths, _ = expected_trace()
        if Counter(observed) != expected_paths:
            raise AssertionError(f"Superseded/closed/stale pending demand reached HTTP: {Counter(observed)-expected_paths}")
        expected_barriers = {f"{kind}-{r}" for kind in ("active-old", "close-old") for r in range(3)}
        if set(Handler.barriers) != expected_barriers or any(not a.is_set() or not b.is_set() for a, b in Handler.barriers.values()):
            raise AssertionError("Missing real active-request barriers or releases")
        for damaged in (process.stdout.replace("http,delayed,1,1,1,10", "http,delayed,1,1,1,11", 1),
                        process.stdout.replace("retained,closed,62", "retained,closed,64", 1),
                        process.stdout.replace("page,held-duplicate", "page,held-old", 1),
                        process.stdout.replace("hit,reopened-search,data.txt,1,7,6,12", "hit,reopened-search,data.txt,1,7,7,13", 1),
                        "\n".join(process.stdout.splitlines()[1:])):
            try: validate(damaged)
            except (AssertionError, ValueError, IndexError): pass
            else: raise AssertionError("Oracle accepted corrupt document/identity/result trace")
        print(f"Document services: {metrics['http_requests']} HTTP, {metrics['search_requests']} searches, "
              f"{metrics['rejected_completions']} obsolete/duplicate deliveries rejected across 3 application lifetimes")
        return process
    finally:
        for _, release in Handler.barriers.values(): release.set()
        server.shutdown(); server.server_close(); thread.join()


if __name__ == "__main__":
    run(sys.argv[1])
