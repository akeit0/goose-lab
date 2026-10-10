// Expected diagnostic on the recorded revisions: descriptor read loses pool provenance.
import std;
import os;
reusable[] var pool: u8[>..] = [];
struct Descriptor { bytes: u8[:] = pool[..0] }
var descriptor = Descriptor {};
fn main() {
    let argv = args();
    descriptor.bytes = pool.alloc_slice(8);
    print(argv.len, " ", pool.index_of(descriptor.bytes[0]));
}
