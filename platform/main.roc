platform ""
    requires {} { main! : {} => Try({}, [Exit(I32)]) }
    exposes [Stdout, Stderr, WebServer]
    packages {}
    provides { main_for_host!: "main_for_host" }
    targets: {
        files: "targets/",
        exe: {
            x64mac: ["libhost.a", app],
            arm64mac: ["libhost.a", app],
            x64musl: ["crt1.o", "libhost.a", app, "libc.a"],
            x64glibc: ["libhost.a", app],
            arm64musl: ["crt1.o", "libhost.a", app, "libc.a"],
            x64win: ["host.lib", app],
            arm64win: ["host.lib", app],
            wasm32: ["libhost.a", app],
        }
    }

import Stdout
import Stderr
import WebServer


main_for_host! : {} => I32
main_for_host! = |{}| {
    result = main!({})
    match result {
        Ok({}) => 0
        Err(Exit(code)) => code
    }
}
