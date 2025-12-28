app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import JsonDecode

main! : {} => Try({}, [Exit(I32)])
main! = |{}| {
    # Test decoding a Str from JSON
    string_bytes = "\"hello world\"".to_utf8()
    string_result = JsonDecode.decode_str(string_bytes)
    
    str_msg = match string_result.result {
        Ok(s) => "Decoded string: ${s}"
        Err(TooShort) => "Failed to decode string: TooShort"
    }
    Stdout.line!(str_msg)
    
    # Test decoding a number
    num_bytes = "42".to_utf8()
    num_result = JsonDecode.decode_u64(num_bytes)
    
    num_msg = match num_result.result {
        Ok(_) => "Decoded number successfully"
        Err(TooShort) => "Failed to decode number: TooShort"
    }
    Stdout.line!(num_msg)
    
    # Test decoding a bool
    bool_bytes = "true".to_utf8()
    bool_result = JsonDecode.decode_bool(bool_bytes)
    
    bool_msg = match bool_result.result {
        Ok(b) => if b { "Decoded bool: true" } else { "Decoded bool: false" }
        Err(TooShort) => "Failed to decode bool: TooShort"
    }
    Stdout.line!(bool_msg)
    
    Stdout.line!("Done!")
    Ok({})
}
