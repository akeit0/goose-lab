// Run only as an isolated child built with GS_STACK_RESERVE=1048576.
// Single oversized requests and cumulative exhaustion have different diagnostics.
import std;
import os;
fn main() {
    let argv = args(); assert(argv.len == 2);
    reusable[] var pool: u8[>..] = [];
    if argv[1] == "single" {
        let run = pool.alloc_slice(2097152);
        print("unexpected allocation success ", run.len);
    } else {
        assert(argv[1] == "cumulative");
        let first = pool.alloc_slice(786432);
        let second = pool.alloc_slice(786432);
        print("unexpected allocation success ", first.len, " ", second.len);
    }
}
