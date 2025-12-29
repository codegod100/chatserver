# Memory Leak Investigation

## Problem
The chat server was experiencing rapid memory growth, consuming gigabytes of RAM within seconds of starting.

## Root Cause
The Roc interpreter had a bug where it didn't properly free stack memory after function calls. The `stack_memory.restore()` function was never called, causing unbounded stack growth. The original `event_loop!` function called itself recursively:

```roc
event_loop! = || {
    event = WebServer.accept!()
    match event {
        Connected(_) => { ...; event_loop!() }
        Message(_, _) => { ...; event_loop!() }
        ...
    }
}
```

Each recursive call allocated stack memory that was never reclaimed.

## Interpreter Fix (Patched)

The fix was implemented in `src/eval/interpreter.zig`:

1. **Added `saved_stack_ptr` field to `CallCleanup` struct** - Stores the stack pointer checkpoint before function call setup.

2. **Save stack pointer in `call_invoke_closure`** - Right after switching to the closure's environment, save the current stack position.

3. **Restore stack in `call_cleanup`** - After the function body completes:
   - For results that don't point into the callee's stack frame, simply restore the stack.
   - For results that do point into the callee's stack (scalar values), relocate the result data to the caller's frame before restoration.
   - For heap-allocated data (strings, lists), the refcount mechanism keeps them alive regardless of stack restoration.

## Additional Issues Found

### 1. Triple-quoted strings with interpolation
Roc's triple-quoted strings (`"""..."""`) with variable interpolation were including the closing `"""` as literal text:
```roc
# This produced: {"type": "system"}"""
msg = """{"type": "system"}"""
```
**Fix**: Use regular escaped strings instead.

### 2. Heap-allocated RocStr return values
Hosted functions returning `RocStr` via `RocStr.init()` were leaking because the interpreter wasn't decrementing refcounts properly.
**Mitigation**: Use `RocStr.fromSliceSmall()` for strings < 24 bytes to avoid heap allocation.

## Workaround (Before Interpreter Fix)
Before the interpreter fix was available, the workaround was to move the event loop from Roc to Zig:

1. Roc calls `WebServer.run!()` which blocks
2. Zig handles the entire event loop internally
3. No Roc recursion = no interpreter memory leak

```roc
main! = |{}| {
    WebServer.listen!(8080)
    WebServer.run!()  # Blocks forever, loop runs in Zig
}
```

## Files Changed
- `app/main.roc` - Removed recursive `event_loop!`, now just calls `run!`
- `platform/WebServer.roc` - Replaced `accept!` with `run!`
- `platform/host.zig` - Added `hostedWebServerRun` with full event loop
- Removed `platform/Json.roc` - No longer needed, events are ADTs from Zig

## Lessons Learned
1. ~~Avoid recursion in Roc effectful functions until the interpreter is fixed~~ (Fixed!)
2. Prefer small strings (< 24 bytes) to avoid heap allocation
3. Move hot loops to Zig when possible (still good for performance)
