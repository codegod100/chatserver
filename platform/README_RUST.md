# Rust Platform Implementation

This platform has been ported from Zig to Rust. The implementation provides the same WebSocket server functionality as the original Zig version.

## FFI Interface

The Rust implementation exports the following C-compatible functions that match the platform definition:

- `webserver_listen` - Start the WebSocket server on a given port
- `webserver_accept` - Accept and return the next WebSocket event as JSON
- `webserver_send` - Send a message to a specific client
- `webserver_broadcast` - Broadcast a message to all connected clients
- `webserver_close` - Close a client connection
- `stdout_line` - Write a line to stdout
- `stderr_line` - Write a line to stderr

## Building

The Rust platform is built using Cargo:

```bash
cd platform
cargo build --release
```

The build script (`../build_rust.sh`) will automatically:
1. Detect your Rust target
2. Build the library
3. Copy it to the appropriate `targets/` directory for Roc

## FFI Compatibility Note

The exact calling convention may need to be adjusted based on the specific Roc Rust runtime being used. The current implementation uses a simplified FFI structure that should be compatible, but may require modification to match Roc's exact ABI requirements.

Key areas that might need adjustment:
- RocStr structure layout
- Function calling conventions
- Memory allocation/deallocation hooks
- Error handling and result types

## Architecture

The implementation uses:
- Thread-based I/O (non-blocking sockets with polling)
- Arc/Mutex for shared state between threads
- Standard library networking (no external async runtime required)
- SHA1 and Base64 for WebSocket handshake

The server handles:
- HTTP requests for static file serving
- WebSocket upgrade requests
- WebSocket frame parsing and generation
- Client connection management
- Message broadcasting


