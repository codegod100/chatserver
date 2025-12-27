# Known Issues

## Roc Compiler Panic

When building the application with Roc, you may encounter:

```
thread 'main' panicked at crates/compiler/load_internal/src/file.rs:1791:37:
There were still outstanding Arc references to module_ids
```

This is an **internal bug in the Roc compiler** (nightly build), not an issue with the platform code. This appears to be a memory management issue in the compiler itself that occurs when loading packages (particularly the `json` package).

### Related GitHub Issues

- **[Issue #7429](https://github.com/roc-lang/roc/issues/7429)**: "Outstanding references to the derived module" - Similar panic related to module references
- **[Issue #5152](https://github.com/roc-lang/roc/issues/5152)**: "panic on platform requires header without type annotation" - Similar panic at `file.rs:1842:37` (same file, different line)
- **[Issue #3609](https://github.com/roc-lang/roc/issues/3609)**: Related to using the `json` package on Linux, but requires `--linker=legacy` flag (this is a different issue - linking, not compilation)

### Workarounds Attempted

1. ✅ **Fixed platform syntax error**: Removed invalid `imports` line from `platform/main.roc`
2. ❌ **`--linker=legacy` flag**: Does not fix this issue (panic occurs during compilation, not linking)
3. ❌ **Simplified test case**: Even minimal code using `json` package triggers the panic

### Recommended Actions

1. **Try a different Roc build**: This might be fixed in a newer or older nightly build
   - Current version: `roc nightly pre-release, built from commit d73ea109 on Tue 09 Sep 2025`
2. **Report the bug**: If not already covered by the issues above, report to the Roc team on GitHub with:
   - Minimal reproduction case (see `app/test.roc`)
   - Full backtrace with `RUST_BACKTRACE=full`
   - Roc version information
   - Reference to similar issues #7429 and #5152
3. **Workaround**: Consider avoiding the `json` package temporarily or using a different JSON parsing approach

### Status

- Platform code: ✅ Complete and compiles
- Zig host library: ✅ Builds successfully  
- Elm frontend: ✅ Builds successfully
- Roc application build: ❌ Blocked by compiler bug

The platform implementation is complete and should work once the compiler issue is resolved.
