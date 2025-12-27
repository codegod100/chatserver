# Roc Tag Union ABI Reference

This document describes the memory layout and ABI conventions for Roc tag unions when implementing platform host functions in Zig (or other languages). This information was gathered from analysis of the Roc compiler source code (December 2024).

## Overview

When a Roc function returns a tag union (like `Event` or `Result`), the host must write the value into a memory buffer (`ret_ptr`) following a specific layout that the Roc interpreter expects.

## Key Concepts

### 1. Tag Ordering (Discriminant Assignment)

**Tags are sorted alphabetically by name.** The discriminant value (tag ID) is assigned based on this alphabetical order.

From `roc/crates/compiler/mono/src/layout.rs` line 4044:
```rust
tags_vec.sort_unstable_by(|(a, _), (b, _)| a.cmp(b));
```

#### Example: Event Type

```roc
Event : [
    Connected { clientId : U64 },
    Disconnected { clientId : U64 },
    Message { clientId : U64, text : Str },
    Error { message : Str },
    Shutdown,
]
```

Alphabetically sorted:
| Tag Name     | Discriminant |
|--------------|--------------|
| Connected    | 0            |
| Disconnected | 1            |
| Error        | 2            |
| Message      | 3            |
| Shutdown     | 4            |

### 2. Memory Layout

**The layout is: payload first, then discriminant at the end.**

From `roc/src/layout/store.zig` lines 1020-1023:
```zig
// Calculate total size: payload at offset 0, discriminant at aligned offset after payload
const payload_end = max_payload_size;
const discriminant_offset: u16 = @intCast(std.mem.alignForward(u32, payload_end, @intCast(discriminant_alignment.toByteUnits())));
```

The `TagUnionData` structure (from `roc/src/layout/layout.zig` lines 261-268):
```zig
pub const TagUnionData = struct {
    size: u32,                    // Total size including discriminant and padding
    discriminant_offset: u16,     // Offset where discriminant is stored
    discriminant_size: u8,        // 1, 2, or 4 bytes
    variants: NonEmptyRange,      // Range of variant layouts
};
```

### 3. Discriminant Size

The discriminant size depends on the number of tags:

From `roc/crates/compiler/mono/src/layout.rs` lines 1181-1186:
```rust
pub const fn from_number_of_tags(tags: usize) -> Self {
    match tags {
        0 => Discriminant::U0,      // 0 bytes
        1 => Discriminant::U0,      // 0 bytes (no discriminant needed)
        2 => Discriminant::U1,      // 1 byte (stored as u8)
        3..=255 => Discriminant::U8,    // 1 byte
        256..=65_535 => Discriminant::U16,  // 2 bytes
        _ => panic!("discriminant too large"),
    }
}
```

**Note:** Even `U1` (for 2-tag unions) uses 1 byte of storage (stored as u8).

### 4. Payload Field Ordering

Within each variant's payload, **fields are sorted by alignment (descending), then by name (ascending)**.

From `roc/crates/compiler/mono/src/layout.rs` lines 4794-4795:
```rust
size2.cmp(&size1).then(label1.cmp(label2))
```

This means:
- Larger-aligned fields come first (e.g., U64 before Str if Str has smaller alignment)
- For fields with the same alignment, alphabetical order is used

### 5. Reading the Discriminant

The interpreter reads discriminants using little-endian byte order:

From `roc/src/layout/layout.zig` lines 279-284:
```zig
pub fn readDiscriminant(self: TagUnionData, base_ptr: [*]const u8) u32 {
    const disc_ptr = base_ptr + self.discriminant_offset;
    return switch (self.discriminant_size) {
        1 => disc_ptr[0],
        2 => @as(u32, disc_ptr[0]) | (@as(u32, disc_ptr[1]) << 8),
        4 => @as(u32, disc_ptr[0]) | (@as(u32, disc_ptr[1]) << 8) | 
             (@as(u32, disc_ptr[2]) << 16) | (@as(u32, disc_ptr[3]) << 24),
        else => unreachable,
    };
}
```

## Calculating Layout for Your Type

### Step-by-Step Process

1. **List all tag names and sort alphabetically** → assigns discriminant values
2. **For each variant, determine payload layout:**
   - If no payload: size = 0
   - If single field: use that field's layout
   - If multiple fields (record): sort fields by alignment desc, then name asc
3. **Find the largest payload** → this is `max_payload_size`
4. **Determine discriminant size** based on number of tags
5. **Calculate discriminant offset:** 
   - `discriminant_offset = align_forward(max_payload_size, discriminant_alignment)`
6. **Calculate total size:**
   - `total_size = align_forward(discriminant_offset + discriminant_size, max_alignment)`

### Example: Event Type Layout

```roc
Event : [
    Connected { clientId : U64 },      # Payload: U64 (8 bytes)
    Disconnected { clientId : U64 },   # Payload: U64 (8 bytes)
    Message { clientId : U64, text : Str },  # Payload: U64 + Str (8 + 24 = 32 bytes)
    Error { message : Str },           # Payload: Str (24 bytes)
    Shutdown,                          # Payload: none (0 bytes)
]
```

**RocStr layout:** 24 bytes (pointer + length + capacity or inline small string)

Calculation:
- 5 tags → discriminant size = 1 byte (U8)
- Largest payload = `Message` = 32 bytes (U64 at 8-byte alignment + Str at 8-byte alignment)
- discriminant_offset = align_forward(32, 1) = 32
- Total size = align_forward(32 + 1, 8) = 40 bytes

**Memory Layout (40 bytes):**
```
Offset 0-7:   clientId (U64) for Connected/Disconnected/Message
              OR first 8 bytes of message Str for Error
Offset 8-31:  text (RocStr) for Message
              OR remaining bytes of message Str for Error
              OR padding for Connected/Disconnected/Shutdown
Offset 32:    discriminant (u8)
Offset 33-39: padding to 8-byte alignment
```

## Zig Implementation Example

```zig
// For Event type with 5 variants
const EventResult = extern struct {
    // Payload union - sized to largest variant (Message = 32 bytes)
    payload: extern union {
        // Connected/Disconnected: just clientId at offset 0
        client_id: u64,
        
        // Error: Str at offset 0
        err_message: RocStr,
        
        // Message: clientId at offset 0, text at offset 8
        message: extern struct {
            client_id: u64,
            text: RocStr,
        },
        
        // Shutdown: no payload (but union still takes 32 bytes)
    },
    
    // Discriminant at offset 32
    discriminant: u8,
    
    // Implicit padding: 7 bytes to reach 40 total
};

comptime {
    // Verify our layout matches Roc's expectations
    std.debug.assert(@sizeOf(EventResult) == 40);
    std.debug.assert(@offsetOf(EventResult, "discriminant") == 32);
}
```

## Common Pitfalls

### 1. Wrong Tag Order
Tags must be in **alphabetical** order, not declaration order.

### 2. Wrong Discriminant Offset
The discriminant is at the **end** of the payload, not the beginning. Calculate it as:
```
discriminant_offset = align_forward(max_payload_size, discriminant_alignment)
```

### 3. RocStr Small String Optimization Confusion
When `RocStr` uses small-string optimization, the last byte contains `0x80 | length`. This can look like garbage if you're debugging raw bytes. Don't confuse this with the discriminant.

### 4. Alignment Issues
- Use `extern struct` in Zig to get C ABI layout
- Payload fields must be properly aligned
- The discriminant must be aligned to its natural alignment (1 for u8, 2 for u16)

### 5. Not Handling All Variants
Every variant in the tag union must be accounted for in your union type, even if it has no payload (like `Shutdown`).

## Union Variants with Record Payloads

When a tag has a record payload like `Message { clientId : U64, text : Str }`:

1. Fields are sorted: alignment descending, then name ascending
2. For `Message`: both `clientId` (U64) and `text` (Str) have 8-byte alignment
3. Alphabetically: `clientId` < `text`
4. So order is: `clientId` first, then `text`

```zig
message: extern struct {
    client_id: u64,  // offset 0, sorted first (same alignment, 'c' < 't')
    text: RocStr,    // offset 8
},
```

## Debugging Tips

1. **Print struct sizes and offsets:**
```zig
std.debug.print("size={}, disc_offset={}\n", .{
    @sizeOf(EventResult),
    @offsetOf(EventResult, "discriminant"),
});
```

2. **Print raw bytes after writing:**
```zig
const bytes = @as([*]const u8, @ptrCast(result))[0..@sizeOf(EventResult)];
for (bytes) |b| {
    std.debug.print("{x:0>2} ", .{b});
}
```

3. **Verify your discriminant values:**
```zig
// After writing
std.debug.print("discriminant byte at offset {}: {}\n", .{
    @offsetOf(EventResult, "discriminant"),
    result.discriminant,
});
```

## Troubleshooting

### Symptom: Values Displayed as Floats/Garbage

If `Str.inspect(event)` shows values like `36039766707.3687927` instead of a proper tag union, this indicates a fundamental layout mismatch. The interpreter is reading your tag union bytes and interpreting them as a different type entirely.

**Possible causes:**

1. **Hosted function index mismatch** - The interpreter is calling the wrong host function. Check that your `hosted_function_ptrs` array is in correct alphabetical order by fully-qualified name.

2. **Type variable resolution issue** - The interpreter's type for the return value may not match `Event`. This can happen if type inference fails or if there's a mismatch between the platform declaration and the host implementation.

3. **Layout computation differs** - The interpreter computed a different layout than expected. Add debug output to verify sizes and offsets match.

### Symptom: Wrong Tag Variant Matched

If your `match` statement always hits the wrong branch or the `_` fallback:

1. **Wrong discriminant value** - Verify you're using alphabetical ordering for tag names
2. **Wrong discriminant offset** - The discriminant must be at `align_forward(max_payload_size, discriminant_alignment)`
3. **Wrong discriminant size** - Check the number of variants to determine if it's 1, 2, or 4 bytes

### Symptom: Payload Data is Corrupted

If the tag is correct but payload fields contain wrong values:

1. **Field ordering wrong** - Record fields must be sorted by alignment (descending), then name (ascending)
2. **Alignment padding missing** - Fields must be aligned within the struct
3. **RocStr not initialized correctly** - Use `RocStr.init()` from builtins, not manual construction

### Debug Checklist

```zig
// 1. Verify struct layout at compile time
comptime {
    std.debug.assert(@sizeOf(EventResult) == 40);
    std.debug.assert(@offsetOf(EventResult, "discriminant") == 32);
}

// 2. Print layout info at runtime
std.debug.print("EventResult: size={}, disc_offset={}\n", .{
    @sizeOf(EventResult),
    @offsetOf(EventResult, "discriminant"),
});

// 3. Print raw bytes after writing
const bytes = @as([*]const u8, @ptrCast(result))[0..@sizeOf(EventResult)];
std.debug.print("Raw bytes: ", .{});
for (bytes) |b| std.debug.print("{x:0>2} ", .{b});
std.debug.print("\n", .{});

// 4. Verify discriminant value
std.debug.print("Written discriminant: {}\n", .{result.discriminant});
```

### Adding Interpreter Debug Output

If you have access to the Roc source, add debug output in `roc/src/eval/interpreter.zig` around `callHostedFunction`:

```zig
// After line 1236
std.debug.print("Hosted fn {}: return layout size={}, tag={s}\n", .{
    hosted_fn_index,
    self.runtime_layout_store.layoutSize(return_layout),
    @tagName(return_layout.tag),
});
```

## Hosted Function Ordering

**CRITICAL:** Hosted functions must be provided in alphabetical order by their fully-qualified name (with `!` stripped).

From `roc/src/canonicalize/HostedCompiler.zig` lines 145-202:
```zig
/// Collect all hosted functions from the module (transitively through imports)
/// and sort them alphabetically by fully-qualified name (with `!` stripped).

// Strip the `!` suffix for sorting (e.g., "Stdout.line!" -> "Stdout.line")
const stripped_name = if (std.mem.endsWith(u8, qualified_name, "!"))
    qualified_name[0 .. qualified_name.len - 1]
else
    qualified_name;

// Sort alphabetically by stripped qualified name
std.mem.sort(HostedFunctionInfo, hosted_fns.items, {}, SortContext.lessThan);
```

### Example: WebServer Platform

Given these hosted modules:
```roc
Stderr := [].{ line! : Str => {} }
Stdout := [].{ line! : Str => {} }
WebServer := [].{
    listen! : U16 => [Ok({}), Err(Str)],
    accept! : () => Event,
    send! : U64, Str => [Ok({}), Err(Str)],
    broadcast! : Str => [Ok({}), Err(Str)],
    close! : U64 => {},
}
```

The alphabetically sorted function names (with `!` stripped):
| Index | Fully-Qualified Name  |
|-------|----------------------|
| 0     | Stderr.line          |
| 1     | Stdout.line          |
| 2     | WebServer.accept     |
| 3     | WebServer.broadcast  |
| 4     | WebServer.close      |
| 5     | WebServer.listen     |
| 6     | WebServer.send       |

**Note:** `listen` comes before `send` alphabetically!

### Zig Implementation

```zig
const hosted_function_ptrs = [_]builtins.host_abi.HostedFn{
    hostedStderrLine,         // index 0: Stderr.line
    hostedStdoutLine,         // index 1: Stdout.line
    hostedWebServerAccept,    // index 2: WebServer.accept
    hostedWebServerBroadcast, // index 3: WebServer.broadcast
    hostedWebServerClose,     // index 4: WebServer.close
    hostedWebServerListen,    // index 5: WebServer.listen  <-- 'l' before 's'
    hostedWebServerSend,      // index 6: WebServer.send
};
```

### Common Mistake

If function pointers are in the wrong order, calls will go to the wrong function:
- Calling `listen!` might invoke `send`'s implementation
- Calling `send!` might invoke `listen`'s implementation

This can cause very confusing bugs where the function executes but produces wrong results or crashes.

## Record Payloads in Tag Variants

When a tag has a record payload like `Message { clientId : U64, text : Str }`:

The payload type is `{ clientId : U64, text : Str }` - a record with two fields.

**Important:** The record's fields are sorted independently:
1. By alignment (descending)
2. By field name (ascending)

For `Message { clientId : U64, text : Str }`:
- `clientId` (U64): 8-byte alignment
- `text` (Str): 8-byte alignment  
- Same alignment, so sort by name: `clientId` < `text`
- Result: `clientId` at offset 0, `text` at offset 8

```zig
// Correct layout for Message payload
message: extern struct {
    client_id: u64,  // offset 0 (c < t alphabetically)
    text: RocStr,    // offset 8
},
```

For single-field records like `Error { message : Str }`:
- The record has the same layout as the field itself
- `{ message : Str }` is 24 bytes, same as `Str`

## References

- `roc/crates/compiler/mono/src/layout.rs` - Rust layout computation
- `roc/src/layout/layout.zig` - Zig interpreter layout types
- `roc/src/layout/store.zig` - Layout store and tag union finalization
- `roc/src/eval/StackValue.zig` - Tag union accessor (how interpreter reads values)
- `roc/src/eval/interpreter.zig` - Hosted function calling convention
- `roc/src/canonicalize/HostedCompiler.zig` - Hosted function sorting logic
- `roc/src/eval/render_helpers.zig` - Value rendering (what Str.inspect uses)

## Version Note

This documentation is based on the Roc source code as of December 2024. The ABI may change in future versions. Always verify against the actual Roc interpreter behavior when debugging issues.

## Quick Reference Card

```
Tag Union Layout:
┌─────────────────────────────────┐
│  Payload (max variant size)     │  offset 0
│  ...                            │
├─────────────────────────────────┤
│  Discriminant (1/2/4 bytes)     │  offset = align(payload_size, disc_align)
├─────────────────────────────────┤
│  Padding to struct alignment    │
└─────────────────────────────────┘
  total size = align(disc_offset + disc_size, max_alignment)

Discriminant Size:
  0-1 variants  → 0 bytes (none needed)
  2 variants    → 1 byte (U1 stored as u8)
  3-255 variants → 1 byte (U8)
  256-65535     → 2 bytes (U16)

Tag Ordering: Alphabetical by tag name
Field Ordering: Alignment desc, then name asc
Function Ordering: Alphabetical by qualified name (! stripped)
```