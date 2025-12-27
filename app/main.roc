app [main!] {
    pf: platform "../platform/main.roc",
}

import pf.Stdout
import pf.Stderr
import pf.WebServer

## Chat server that handles WebSocket connections
## and broadcasts messages to all connected clients

main! : {} => Try({}, [Exit(I32)])
main! = |{}| {
    port = 8080
    Stdout.line!("Starting chat server on port ${port.to_str()}...")

    match WebServer.listen!(port) {
        Ok({}) =>
            Stdout.line!("Server listening on http://localhost:${port.to_str()}")
        Err(msg) => {
            Stderr.line!("Failed to start server: ${msg}")
            return Err(Exit(1))
        }
    }

    Stdout.line!("Waiting for connections...")

    event_loop!()
}

event_loop! : () => Try({}, [Exit(I32)])
event_loop! = || {
    json_str = WebServer.accept!()
    Stdout.line!("Event JSON: ${json_str}")

    event = parse_event(json_str)
    Stdout.line!("Parsed event, entering match...")

    match event {
        Connected(client_id) => {
            Stdout.line!("Connected branch, client_id received")
            welcome_msg = "{\"type\": \"system\", \"text\": \"Welcome to the chat! You are client #${client_id.to_str()}\"}"
            match WebServer.send!(client_id, welcome_msg) {
                Ok({}) => {}
                Err(err) => Stdout.line!("Send error: ${err}")
            }
            join_msg = "{\"type\": \"system\", \"text\": \"Client #${client_id.to_str()} joined the chat\"}"
            match WebServer.broadcast!(join_msg) {
                Ok({}) => {}
                Err(err) => Stdout.line!("Broadcast error: ${err}")
            }
            event_loop!()
        }

        Disconnected(client_id) => {
            Stdout.line!("Client ${client_id.to_str()} disconnected")
            leave_msg = "{\"type\": \"system\", \"text\": \"Client #${client_id.to_str()} left the chat\"}"
            match WebServer.broadcast!(leave_msg) {
                Ok({}) => {}
                Err(err) => Stdout.line!("Broadcast error: ${err}")
            }
            event_loop!()
        }

        Message(client_id, text) => {
            Stdout.line!("Client ${client_id.to_str()}: ${text}")
            broadcast_msg = "{\"type\": \"message\", \"clientId\": ${client_id.to_str()}, \"text\": \"${text}\"}"
            match WebServer.broadcast!(broadcast_msg) {
                Ok({}) => {}
                Err(err) => Stdout.line!("Broadcast error: ${err}")
            }
            event_loop!()
        }

        Error(message) => {
            Stdout.line!("Error: ${message}")
            event_loop!()
        }

        Shutdown => {
            Stdout.line!("Server shutting down")
            Ok({})
        }

        Unknown => {
            Stdout.line!("Unknown event received: ${json_str}")
            event_loop!()
        }
    }
}

Event : [
    Connected(U64),
    Disconnected(U64),
    Message(U64, Str),
    Error(Str),
    Shutdown,
    Unknown,
]

parse_event : Str -> Event
parse_event = |json_str| {
    # Simple approach: check for substrings
    if Str.contains(json_str, "\"type\":\"connected\"") or Str.contains(json_str, "\"type\": \"connected\"") {
        # Extract clientId - find the number after "clientId":
        client_id = extract_client_id(json_str)
        Connected(client_id)
    } else if Str.contains(json_str, "\"type\":\"disconnected\"") or Str.contains(json_str, "\"type\": \"disconnected\"") {
        client_id = extract_client_id(json_str)
        Disconnected(client_id)
    } else if Str.contains(json_str, "\"type\":\"message\"") or Str.contains(json_str, "\"type\": \"message\"") {
        client_id = extract_client_id(json_str)
        text = get_json_string(json_str, "text")
        Message(client_id, text)
    } else if Str.contains(json_str, "\"type\":\"error\"") or Str.contains(json_str, "\"type\": \"error\"") {
        err_msg = get_json_string(json_str, "message")
        Error(err_msg)
    } else if Str.contains(json_str, "\"type\":\"shutdown\"") or Str.contains(json_str, "\"type\": \"shutdown\"") {
        Shutdown
    } else {
        Unknown
    }
}

# Extract client ID by finding digits after "clientId":
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

# Get a string value from JSON by key
get_json_string : Str, Str -> Str
get_json_string = |json_str, key| {
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
                        match extracted.to_str() {
                            Ok(s) => s
                            Err(_) => default
                        }
                    }
                    _ => default
                }
            } else {
                find_and_extract_string(rest, key_pattern, default)
            }
        }
    }
}

# Check if bytes starts with pattern using index-based comparison
check_prefix : List(U8), List(U8), U64 -> Bool
check_prefix = |bytes, pattern, idx| {
    if idx >= List.len(pattern) {
        True
    } else if idx >= List.len(bytes) {
        False
    } else {
        b = List.get(bytes, idx)
        p = List.get(pattern, idx)
        match (b, p) {
            (Ok(bv), Ok(pv)) => {
                if bv == pv {
                    check_prefix(bytes, pattern, idx + 1)
                } else {
                    False
                }
            }
            _ => False
        }
    }
}

# Get a number value from JSON by key
get_json_number : Str, Str -> U64
get_json_number = |json_str, key| {
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
