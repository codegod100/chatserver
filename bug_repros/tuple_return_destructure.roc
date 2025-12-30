app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout

## Bug: Tuple return with destructuring crashes
## Error: Roc crashed: Internal error: pattern match failed in bind_def continuation

get_pair : {} -> (U64, Str)
get_pair = |{}| {
    (42, "Hello")
}

main! = |{}| {
    (num, text) = get_pair({})
    
    Stdout.line!("${num.to_str()}: ${text}")
    Ok({})
}
