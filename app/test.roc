app [main!] {
    pf: platform "../platform/main.roc",
    json: "https://github.com/lukewilliamboswell/roc-json/releases/download/0.13.0/RqendgZw5e1RsQa3kFhgtnMP8efWoqGRsAvubx4-zus.tar.br",
}

import pf.Stdout
import json.Json

TestRecord : { name : Str }

main! : {} => Try({}, [Exit(I32)])
main! = |{}| {
    bytes = Str.to_utf8("{\"name\":\"test\"}")
    result : [Ok(TestRecord), Err(_)]
    result = Decode.from_bytes(bytes, Json.utf8)
    Stdout.line!("Done")
    Ok({})
}
