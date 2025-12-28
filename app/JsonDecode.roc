## A simple JSON format for use with Decode.from_bytes
## 
## Example usage:
##   Decode.from_bytes(json_bytes, JsonDecode.utf8)

JsonDecode := [Utf8].{
    # The default UTF-8 JSON format
    utf8 : JsonDecode
    utf8 = Utf8
    
    # Decode a U64 from JSON bytes
    decode_u64 : List(U8) -> { result: [Ok(U64), Err([TooShort])], rest: List(U8) }
    decode_u64 = |bytes| {
        trimmed = skip_ws(bytes)
        parse_number(trimmed, 0, False)
    }
    
    # Decode a Str from JSON bytes (expects "..." format)
    decode_str : List(U8) -> { result: [Ok(Str), Err([TooShort])], rest: List(U8) }
    decode_str = |bytes| {
        trimmed = skip_ws(bytes)
        match trimmed {
            ['"', .. as after_quote] => extract_string(after_quote, [])
            _ => { result: Err(TooShort), rest: bytes }
        }
    }
    
    # Decode a Bool from JSON bytes
    decode_bool : List(U8) -> { result: [Ok(Bool), Err([TooShort])], rest: List(U8) }
    decode_bool = |bytes| {
        trimmed = skip_ws(bytes)
        match trimmed {
            ['t', 'r', 'u', 'e', .. as rest] => { result: Ok(True), rest: rest }
            ['f', 'a', 'l', 's', 'e', .. as rest] => { result: Ok(False), rest: rest }
            _ => { result: Err(TooShort), rest: bytes }
        }
    }
}

# Skip whitespace in JSON
skip_ws : List(U8) -> List(U8)
skip_ws = |bytes| match bytes {
    [b, .. as rest] => {
        if b == ' ' or b == '\n' or b == '\r' or b == '\t' {
            skip_ws(rest)
        } else {
            bytes
        }
    }
    _ => bytes
}

parse_number : List(U8), U64, Bool -> { result: [Ok(U64), Err([TooShort])], rest: List(U8) }
parse_number = |bytes, acc, found_digit| match bytes {
    [b, .. as rest] => {
        if b >= '0' and b <= '9' {
            digit = match b {
                '0' => 0u64
                '1' => 1u64
                '2' => 2u64
                '3' => 3u64
                '4' => 4u64
                '5' => 5u64
                '6' => 6u64
                '7' => 7u64
                '8' => 8u64
                _ => 9u64
            }
            parse_number(rest, acc * 10 + digit, True)
        } else if found_digit {
            { result: Ok(acc), rest: bytes }
        } else {
            { result: Err(TooShort), rest: bytes }
        }
    }
    [] => {
        if found_digit {
            { result: Ok(acc), rest: [] }
        } else {
            { result: Err(TooShort), rest: [] }
        }
    }
}

extract_string : List(U8), List(U8) -> { result: [Ok(Str), Err([TooShort])], rest: List(U8) }
extract_string = |bytes, acc| match bytes {
    ['"', .. as rest] => {
        { result: Ok(Str.from_utf8_lossy(acc)), rest: rest }
    }
    ['\\', escaped, .. as rest] => {
        unescaped = match escaped {
            'n' => '\n'
            'r' => '\r'
            't' => '\t'
            '"' => '"'
            '\\' => '\\'
            _ => escaped
        }
        extract_string(rest, List.append(acc, unescaped))
    }
    [b, .. as rest] => extract_string(rest, List.append(acc, b))
    [] => { result: Err(TooShort), rest: [] }
}
