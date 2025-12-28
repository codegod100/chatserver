# JSON Decoder using Roc's Decode Builtin

## Summary

This documents an experimental approach to refactor JSON parsing to use Roc's built-in `Decode` module instead of manual parsing.

**Status: WORKING** - Basic decoding of strings, numbers, and booleans works.

## Files Created

- `app/JsonDecode.roc` - Type module implementing JSON decode methods
- `app/test_json_decode.roc` - Test app demonstrating usage

## How Roc's Decode Builtin Works

The `Decode` module in `Builtin.roc` provides:

```roc
Decode :: [].{
    # Decode bytes, expect no leftover
    from_bytes : List(U8), fmt -> Try(val, [Leftover(List(U8)), TooShort, ..others])
        where [val.decoder : fmt -> val, fmt.decode_bytes : fmt, List(U8) -> { result: Try(val, [TooShort, ..others]), rest: List(U8) }]

    # Decode bytes, allow leftover
    from_bytes_partial : List(U8), fmt -> { result: Try(val, [TooShort, ..others]), rest: List(U8) }
        where [val.decoder : fmt -> val, fmt.decode_bytes : fmt, List(U8) -> { result: Try(val, [TooShort, ..others]), rest: List(U8) }]
}
```

To use `Decode.from_bytes`, you need:
1. A **format type** (e.g., `JsonDecode`) with a `decode_bytes` method
2. A **target type** with a `decoder` method that returns the format-specific decoder

## Our Implementation

### JsonDecode.roc

```roc
JsonDecode := [Utf8].{
    utf8 : JsonDecode
    utf8 = Utf8
    
    # Using inline tag unions [Ok(T), Err([TooShort])] instead of Result/Try
    decode_u64 : List(U8) -> { result: [Ok(U64), Err([TooShort])], rest: List(U8) }
    decode_str : List(U8) -> { result: [Ok(Str), Err([TooShort])], rest: List(U8) }
    decode_bool : List(U8) -> { result: [Ok(Bool), Err([TooShort])], rest: List(U8) }
}
```

### Usage

```roc
import JsonDecode

# Decode a string
result = JsonDecode.decode_str("\"hello\"".to_utf8())
match result.result {
    Ok(s) => # use s
    Err(TooShort) => # handle error
}

# Decode a number
num_result = JsonDecode.decode_u64("42".to_utf8())

# Decode a boolean
bool_result = JsonDecode.decode_bool("true".to_utf8())
```

## Key Implementation Notes

1. **Use inline tag unions** - Write `[Ok(T), Err([TooShort])]` instead of `Result(T, [TooShort])` or `Try(T, [TooShort])`. The `Result` type doesn't exist in Roc; use `Try` for the platform main signature.

2. **Use `True`/`False` not `Bool.true`/`Bool.false`** - Boolean literals are just `True` and `False`.

3. **Closed tag unions work** - Open tag unions `[TooShort, ..others]` can cause interpreter issues. Using closed unions `[TooShort]` works reliably.

## Comparison with Current Approach

| Aspect | Manual Parser (`app/Json.roc`) | Decode-based (`app/JsonDecode.roc`) |
|--------|-------------------------------|-------------------------------------|
| Compiles | ✅ Yes | ✅ Yes |
| Runs | ✅ Yes | ✅ Yes |
| Type-safe | ⚠️ Returns defaults on error | ✅ Returns tagged result with errors |
| Extensible | ❌ Hard-coded keys | ✅ Composable decoders |
| Complexity | Low (~250 lines) | Medium (~100 lines + future extensions) |

## Next Steps

1. **Add more types** - `decode_list`, `decode_object`
2. **Integrate with Decode.from_bytes** - If compiler adds method extension support
3. **Replace manual parser** - Once stable, migrate `app/Json.roc` usage

## Reference

- Builtin Decode: `/home/nandi/code/roc/src/build/roc/Builtin.roc` (lines ~355-375)
- Low-level decode.zig: `/home/nandi/code/roc/crates/compiler/builtins/bitcode/src/decode.zig` (binary primitives only)
- Type module example: `/home/nandi/code/roc/test/fx/opaque_with_method.roc`
