app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout

## Bug: List of records - field access crashes at runtime
## Error: Roc crashed: Field access on non-record type: zst
## or: Roc crashed: Field access on non-record type: scalar

ClientEntry : { id : U64, name : Str }

find_name : List(ClientEntry), U64 -> Str
find_name = |state, client_id| {
    var $result = "Unknown"
    var $i = 0u64
    while $i < state.len() {
        match state.get($i) {
            Ok(entry) => {
                if entry.id == client_id {
                    $result = entry.name
                }
            }
            Err(_) => {}
        }
        $i = $i + 1
    }
    $result
}

main! = |{}| {
    state : List(ClientEntry)
    state = [{ id: 1, name: "Alice" }]
    
    name = find_name(state, 1)
    Stdout.line!(name)
    Ok({})
}
