app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout

## Bug: for loop with tuple destructuring crashes
## Error: Roc crashed: Internal error: TypeMismatch in for_iterate continuation

main! = |{}| {
    state : List((U64, Str))
    state = [(1u64, "Alice"), (2u64, "Bob")]
    
    var $result = ""
    for (_id, name) in state {
        $result = $result.concat(name)
    }
    
    Stdout.line!($result)
    Ok({})
}
