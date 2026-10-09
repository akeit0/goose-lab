import std;
import os;
import lab.net.http;

fn main() {
    let argv = args();
    let url = if argv.len > 1 { argv[1] } else { "https://example.com/" };
    guard lab_net_http::init() == lab_net_http::OK else {
        write_stderr("HTTP initialization failed\n"); return;
    }
    {
        let response = lab_net_http::get(url);
        if lab_net_http::succeeded(response) {
            print("HTTP ", response.status, " (", response.body.len, " bytes)");
            write_stdout(response.body);
            write_stdout("\n");
        } else {
            write_stderr(str("HTTP error ", response.code, ": ", response.error, "\n"));
        }
    }
    lab_net_http::shutdown();
}
