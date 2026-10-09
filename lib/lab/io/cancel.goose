// One-shot cross-thread signal. The creator owns destroy; copies may signal/query.
namespace lab_io_cancel;
import std;
struct Token { id: u64 = 0 }
extern "glab_cancel_create" fn create_raw() -> u64;
extern "glab_cancel_valid" fn valid_raw(id: u64) -> bool;
extern "glab_cancel_request" fn request_raw(id: u64) -> bool;
extern "glab_cancel_requested" fn requested_raw(id: u64) -> bool;
extern "glab_cancel_destroy" fn destroy_raw(id: u64) -> bool;
fn create() -> Token { Token { id: create_raw() } }
fn valid(token: Token) -> bool { valid_raw(token.id) }
fn request(token: Token) -> bool { request_raw(token.id) }
fn requested(token: Token) -> bool { requested_raw(token.id) }
// Dropping the owner requests cancellation and invalidates all public copies.
// A native operation already using it retains a private lease until completion.
fn destroy(token: Token&) { if token.id != 0 { destroy_raw(token.id); token.id = 0; } }
