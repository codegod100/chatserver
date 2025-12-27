# JSON Module Migration for New Roc Compiler

## Summary

The chatserver app needs JSON parsing to decode events from the WebSocket server. The `roc-json` package (v0.13.0) uses old Roc syntax that's incompatible with the new Roc dev branch compiler.

**Status: MIGRATED** - As of 2025-12-27, the app uses a manual JSON parser instead of the roc-json library.

## Solution Implemented

Instead of using the `roc-json` library with its complex ability-based encoding/decoding system, we implemented a simple manual JSON parser directly in `app/main.roc`. This approach:

1. **Avoids the ability system complexity** - The new Roc's `where` clause system for `Decode.from_bytes` requires types to implement `decoder` and `decode_bytes` methods, which aren't auto-derived for records yet.

2. **Method block syntax limitation** - The `.{}` method block syntax (e.g., `Json.utf8`) doesn't work for user-defined types to expose methods yet - only works for `Builtin.roc`.

3. **Simple and targeted** - The manual parser only handles the specific JSON structure needed for the chat events.

## Implementation Details

The manual JSON parser in `app/main.roc` provides:

- `get_json_string(json_str, key)` - Extract a string value by key
- `get_json_number(json_str, key)` - Extract a U64 number by key  
- `parse_event(json_str)` - Parse JSON into the Event tag union

The parser handles the expected JSON event format:
```json
{"type": "connected", "client_id": 123}
{"type": "message", "client_id": 123, "text": "hello"}
{"type": "disconnected", "client_id": 123}
{"type": "error", "message": "something went wrong"}
{"type": "shutdown"}
```

## New Roc Syntax Reference

The new syntax uses `::` for module definitions and `.{}` blocks for methods:

```roc
ModuleName :: [].{
    method_name : Type -> ReturnType
    method_name = |arg| implementation
}

# Opaque types with methods
TypeName := [Variant1, Variant2].{
    is_eq : TypeName, TypeName -> Bool
}

# Functions with type constraints use where clauses
from_bytes : List(U8), fmt -> Try(val, [...])
    where [val.decoder : fmt -> val, fmt.decode_bytes : ...]
```

## Key Differences from Old Syntax

1. **Type Applications**: Now use parentheses: `List(U8)` instead of `List U8`
2. **Module Definitions**: Use `ModuleName :: [dependencies].{ ... }` syntax
3. **Abilities/Traits**: Replaced with method definitions in `.{}` blocks and `where` clauses
4. **Lambda Syntax**: Uses `|arg|` (same as before in newer roc-json)
5. **Error Handling**: Uses `Try(ok, err)` type
6. **Control Flow**: Uses `match` instead of `when`, braces for blocks
7. **Module Headers**: Old `module [...]` syntax is deprecated - use headerless "type modules"
8. **No Pattern Guards**: `match` branches cannot have `if` guards - use if-else inside the branch body

## Files

- `app/main.roc` - Main app with built-in JSON parsing (no external dependency)
- `vendor/json/Json.roc` - Minimal placeholder (not used)
- `vendor/json/Json.roc.bak` - Original roc-json (old syntax, for reference)

## Compiler Versions

- Working compiler: `debug-5c4a8f3d` (dev branch, commit `5c4a8f3d3b`)
- Build command: `cd ../roc && zig build roc`
- Check command: `../roc/zig-out/bin/roc check app/main.roc`
- Build command: `../roc/zig-out/bin/roc build app/main.roc`

## Future Considerations

When the new Roc compiler supports:
1. User-defined type methods accessible via `TypeName.method_name`
2. Auto-derivation of `decoder` for record types

...the roc-json library could be ported properly. Until then, the manual parser approach works well for simple JSON structures.
