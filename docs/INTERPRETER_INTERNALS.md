# Roc Interpreter Internals & Host Implementation Guide

This document documents critical internal details of the Roc interpreter and host interface, specifically focused on pitfalls encountered during platform development.

## 1. Hosted Function Dispatch (The "Index Mismatch" Trap)

The mechanism by which the Roc interpreter calls host functions is brittle and relies on **strict alphabetical ordering**.

### How it works
1. **Roc Side**: The compiler collects all `hosted` functions (functions declared in `platform` but implemented in the host) that are *actually used or imported* by the application.
2. **Host Side**: The host (`host.zig`) defines an array of function pointers (`hosted_fns`).
3. **The Link**: The interpreter calls function #N in the Roc list by invoking index #N in the host's array. There is no name matching at runtime—it is purely index-based.

### The Sorting Rule
Hosted functions are sorted **alphabetically by their fully qualified name**, with the `!` suffix stripped.

**Example Sorting:**
1. `Stderr.line` (originally `Stderr.line!`)
2. `Stdout.line` (originally `Stdout.line!`)
3. `WebServer.accept` (originally `WebServer.accept!`)

### The "Missing Import" Bug
If your host defines `Stderr.line` at index 0, but the Roc application **does not import** `Stderr`, the Roc compiler generated list will *skip* `Stderr`.

**Result:**
- Roc Index 0 becomes `Stdout.line`
- Host Index 0 remains `Stderr.line`
- **mismatch:** When Roc calls `Stdout.line` (its index 0), the host executes `Stderr.line`.
- **mismatch:** When Roc calls `WebServer.accept` (its index 1), the host executes `Stdout.line`.

**Symptom:**
Return values from the wrong function are interpreted as the expected type, leading to garbage data. For example, a `Void` return from `Stdout.line` might be interpreted as a garbage `Event` tag union.

**Fix:**
Ensure the Roc application (or a widely used platform module) imports *all* modules that contain hosted functions defined in the host.

## 2. Debugging ABI Mismatches

### The "Float" Clue
If `Str.inspect` prints a tag union or struct as a bizarre floating-point number (e.g., `8827881463010.04...`), it usually means the interpreter is reading a memory region containing pointers or integer data as an `F64`.

**Technique: recovering the bytes**
You can convert the float back to hex to see the raw bytes:

```python
import struct
# Replace with your float value
val = 8827881463010.041273756483059721
print(struct.pack('<d', val).hex())
```
*Result:* `15c4397acd0ea042` -> Reversing bytes (little-endian) might reveal pointers or ASCII patterns.

### Verifying Layouts
In your Zig host, always use `comptime` checks to enforce ABI assumptions.

```zig
const EventResult = extern struct { ... };

comptime {
    // Verify total size matches Roc's expectation
    if (@sizeOf(EventResult) != 40) @compileError("Size mismatch");
    // Verify discriminant offset
    if (@offsetOf(EventResult, "discriminant") != 32) @compileError("Offset mismatch");
}
```

## 3. Memory Layout Summary

### Tag Unions
- **Payload**: Stored at offset 0.
- **Discriminant**: Stored *after* the largest payload variant, aligned.
- **Size**: Padded to the alignment of the largest field.
- **Ordering**: Tags are sorted alphabetically to assign discriminant IDs (0, 1, 2...).

### RocStr
- **Size**: 3 words (24 bytes on 64-bit).
- **Small String**: If the last byte has the high bit set (`0x80`), it's a small string. The length is in the lower bits of that byte.
- **Heap String**: Standard pointer + length + capacity.

## 4. Platform Architecture

### The `main_for_host` Pattern
Roc applications typically define `main`. However, the host needs a specific entry point signature.
The platform wraps the user's `main` in `main_for_host`:

```roc
main_for_host! : {} => I32
main_for_host! = |{}| {
    match main!({}) {
        Ok({}) => 0,
        Err(Exit(code)) => code
    }
}
```
This converts the rich `Try` result into a simple integer exit code for the OS.
