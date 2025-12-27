module [
    get_string,
    get_number,
    extract_client_id,
]

## Extract client ID by finding digits after "clientId":
extract_client_id : Str -> U64
extract_client_id = |json_str| {
    # Look for clientId": and extract number
    bytes = json_str.to_utf8()
    extract_client_id_helper(bytes, False, 0)
}

extract_client_id_helper : List(U8), Bool, U64 -> U64
extract_client_id_helper = |bytes, found_colon, acc| match bytes {
    ['c', 'l', 'i', 'e', 'n', 't', 'I', 'd', '"', ':', .. as rest] => 
        extract_client_id_helper(rest, True, 0)
    [b, .. as rest] => {
        if found_colon {
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
                    '9' => 9u64
                    _ => 0u64
                }
                extract_client_id_helper(rest, True, acc * 10 + digit)
            } else if b == ' ' or b == '\t' {
                # Skip whitespace after colon
                extract_client_id_helper(rest, True, acc)
            } else {
                # Non-digit, non-whitespace - we're done
                acc
            }
        } else {
            extract_client_id_helper(rest, False, 0)
        }
    }
    [] => acc
}

## Get a string value from JSON by key
get_string : Str, Str -> Str
get_string = |json_str, key| {
    # Convert to bytes and search manually
    bytes = json_str.to_utf8()
    key_bytes = "\"${key}\":".to_utf8()
    # Find the key and extract string value, return "" if not found
    find_and_extract_string(bytes, key_bytes, "")
}

# Recursively search for key pattern and extract string value
find_and_extract_string : List(U8), List(U8), Str -> Str
find_and_extract_string = |bytes, key_pattern, default| {
    match bytes {
        [] => default
        [_, .. as rest] => {
            if check_prefix(bytes, key_pattern, 0) {
                # Found the key, skip it and extract value
                after_key = List.drop_first(bytes, List.len(key_pattern))
                trimmed = skip_whitespace(after_key)
                match trimmed {
                    ['"', .. as after_quote] => {
                        extracted = extract_string(after_quote)
                        # Use Str.from_utf8_lossy to avoid Result
                        Str.from_utf8_lossy(extracted)
                    }
                    _ => default
                }
            } else {
                find_and_extract_string(rest, key_pattern, default)
            }
        }
    }
}

# Check if bytes starts with pattern using recursive list matching
check_prefix : List(U8), List(U8), U64 -> Bool
check_prefix = |bytes, pattern, idx| {
    # Use a helper that works on slices instead of indices
    pattern_slice = List.drop_first(pattern, idx)
    bytes_slice = List.drop_first(bytes, idx)
    check_prefix_helper(bytes_slice, pattern_slice)
}

check_prefix_helper : List(U8), List(U8) -> Bool
check_prefix_helper = |bytes, pattern| {
    match pattern {
        [] => True
        [p, .. as rest_pattern] => {
            match bytes {
                [] => False
                [b, .. as rest_bytes] => {
                    if b == p {
                        check_prefix_helper(rest_bytes, rest_pattern)
                    } else {
                        False
                    }
                }
            }
        }
    }
}

## Get a number value from JSON by key
get_number : Str, Str -> U64
get_number = |json_str, key| {
    # Look for "key": value pattern
    search_pattern = "\"${key}\":"
    bytes = json_str.to_utf8()
    pattern_bytes = search_pattern.to_utf8()
    
    # Find the pattern
    match find_pattern(bytes, pattern_bytes, 0) {
        Ok(pos) => {
            # Skip to value start
            after_key = bytes.drop_first(pos + pattern_bytes.len())
            trimmed = skip_whitespace(after_key)
            
            # Extract number
            num_bytes = extract_number(trimmed)
            match num_bytes.to_str() {
                Ok(num_str) => {
                    parse_u64(num_str)
                }
                Err(_) => 0
            }
        }
        Err(_) => 0
    }
}

# Parse U64 manually to avoid potential crashes
parse_u64 : Str -> U64
parse_u64 = |s| {
    bytes = s.to_utf8()
    parse_u64_helper(bytes, 0)
}

parse_u64_helper : List(U8), U64 -> U64
parse_u64_helper = |bytes, acc| match bytes {
    [b, .. as rest] => {
        if b >= '0' and b <= '9' {
            # Convert digit by matching on the byte value
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
                '9' => 9u64
                _ => 0u64
            }
            parse_u64_helper(rest, acc * 10 + digit)
        } else {
            acc
        }
    }
    [] => acc
}

# Find a pattern in bytes
find_pattern : List(U8), List(U8), U64 -> Try(U64, [NotFound, ..others])
find_pattern = |bytes, pattern, start| {
    pattern_len = pattern.len()
    bytes_len = bytes.len()
    
    if start + pattern_len > bytes_len {
        Err(NotFound)
    } else {
        slice = bytes.sublist({ start: start, len: pattern_len })
        if slice == pattern {
            Ok(start)
        } else {
            find_pattern(bytes, pattern, start + 1)
        }
    }
}

# Skip whitespace
skip_whitespace : List(U8) -> List(U8)
skip_whitespace = |bytes| match bytes {
    [b, .. as rest] => {
        if b == ' ' or b == '\n' or b == '\r' or b == '\t' {
            skip_whitespace(rest)
        } else {
            bytes
        }
    }
    _ => bytes
}

# Extract string value (after opening quote)
extract_string : List(U8) -> List(U8)
extract_string = |bytes| extract_string_helper(bytes, [])

extract_string_helper : List(U8), List(U8) -> List(U8)
extract_string_helper = |bytes, acc| match bytes {
    ['"', ..] => acc
    ['\\', escaped, .. as rest] => {
        # Handle escape sequences
        unescaped = match escaped {
            'n' => '\n'
            'r' => '\r'
            't' => '\t'
            '"' => '"'
            '\\' => '\\'
            _ => escaped
        }
        extract_string_helper(rest, acc.append(unescaped))
    }
    [b, .. as rest] => extract_string_helper(rest, acc.append(b))
    [] => acc
}

# Extract number value
extract_number : List(U8) -> List(U8)
extract_number = |bytes| extract_number_helper(bytes, [])

extract_number_helper : List(U8), List(U8) -> List(U8)
extract_number_helper = |bytes, acc| match bytes {
    [b, .. as rest] => {
        if is_digit(b) or b == '-' {
            extract_number_helper(rest, acc.append(b))
        } else {
            acc
        }
    }
    [] => acc
}

# Check if byte is a digit
is_digit : U8 -> Bool
is_digit = |b| b >= '0' and b <= '9'
