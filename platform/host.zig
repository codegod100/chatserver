//! WebSocket Chat Server Platform Host
//! Implements a WebSocket server for the Roc chat application
const std = @import("std");
const builtins = @import("builtins");

// Use lower-level C environ access to avoid std.os.environ initialization issues
extern var environ: [*:null]?[*:0]u8;
extern fn getenv(name: [*:0]const u8) ?[*:0]u8;

comptime {
    _ = &environ;
    _ = &getenv;
}

fn initEnviron() void {
    if (@import("builtin").os.tag != .windows) {
        _ = environ;
        _ = getenv("PATH");
    }
}

/// Global flag to track if dbg or expect_failed was called.
var debug_or_expect_called: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

/// Host environment with WebSocket server state
const HostEnv = struct {
    gpa: std.heap.GeneralPurposeAllocator(.{}),
    server: ?*WebSocketServer = null,
};

// Use C allocator for Roc allocations
const c_allocator = std.heap.c_allocator;

/// Roc allocation function using C allocator
fn rocAllocFn(roc_alloc: *builtins.host_abi.RocAlloc, env: *anyopaque) callconv(.c) void {
    _ = env;

    const result = c_allocator.rawAlloc(
        roc_alloc.length,
        std.mem.Alignment.fromByteUnits(@max(roc_alloc.alignment, @alignOf(usize))),
        @returnAddress(),
    );

    roc_alloc.answer = result orelse {
        const stderr: std.fs.File = .stderr();
        stderr.writeAll("\x1b[31mHost error:\x1b[0m allocation failed, out of memory\n") catch {};
        std.process.exit(1);
    };
}

/// Roc deallocation function using C allocator
fn rocDeallocFn(roc_dealloc: *builtins.host_abi.RocDealloc, env: *anyopaque) callconv(.c) void {
    _ = env;
    const slice = @as([*]u8, @ptrCast(roc_dealloc.ptr))[0..0];
    c_allocator.rawFree(
        slice,
        std.mem.Alignment.fromByteUnits(@max(roc_dealloc.alignment, @alignOf(usize))),
        @returnAddress(),
    );
}

/// Roc reallocation function using C allocator
fn rocReallocFn(roc_realloc: *builtins.host_abi.RocRealloc, env: *anyopaque) callconv(.c) void {
    _ = env;

    const align_enum = std.mem.Alignment.fromByteUnits(@max(roc_realloc.alignment, @alignOf(usize)));

    const new_ptr = c_allocator.rawAlloc(roc_realloc.new_length, align_enum, @returnAddress()) orelse {
        const stderr: std.fs.File = .stderr();
        stderr.writeAll("\x1b[31mHost error:\x1b[0m reallocation failed, out of memory\n") catch {};
        std.process.exit(1);
    };

    const old_ptr: [*]const u8 = @ptrCast(roc_realloc.answer);
    @memcpy(new_ptr[0..roc_realloc.new_length], old_ptr[0..roc_realloc.new_length]);

    const old_slice = @as([*]u8, @ptrCast(roc_realloc.answer))[0..0];
    c_allocator.rawFree(old_slice, align_enum, @returnAddress());

    roc_realloc.answer = new_ptr;
}

/// Roc debug function
fn rocDbgFn(roc_dbg: *const builtins.host_abi.RocDbg, env: *anyopaque) callconv(.c) void {
    _ = env;
    debug_or_expect_called.store(true, .release);
    const message = roc_dbg.utf8_bytes[0..roc_dbg.len];
    const stderr = std.fs.File.stderr();
    stderr.writeAll("\x1b[33mdbg:\x1b[0m ") catch {};
    stderr.writeAll(message) catch {};
    stderr.writeAll("\n") catch {};
}

/// Roc expect failed function
fn rocExpectFailedFn(roc_expect: *const builtins.host_abi.RocExpectFailed, env: *anyopaque) callconv(.c) void {
    _ = env;
    debug_or_expect_called.store(true, .release);
    const source_bytes = roc_expect.utf8_bytes[0..roc_expect.len];
    const trimmed = std.mem.trim(u8, source_bytes, " \t\n\r");
    const stderr = std.fs.File.stderr();
    stderr.writeAll("\x1b[33mexpect failed:\x1b[0m ") catch {};
    stderr.writeAll(trimmed) catch {};
    stderr.writeAll("\n") catch {};
}

/// Roc crashed function
fn rocCrashedFn(roc_crashed: *const builtins.host_abi.RocCrashed, env: *anyopaque) callconv(.c) noreturn {
    _ = env;
    const message = roc_crashed.utf8_bytes[0..roc_crashed.len];
    const stderr = std.fs.File.stderr();
    stderr.writeAll("\n\x1b[31mRoc crashed:\x1b[0m ") catch {};
    stderr.writeAll(message) catch {};
    stderr.writeAll("\n") catch {};
    std.process.exit(1);
}

// External symbols provided by the Roc runtime
extern fn roc__main_for_host(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, arg_ptr: ?*anyopaque) callconv(.c) void;

// OS-specific entry point handling
comptime {
    if (!@import("builtin").is_test) {
        @export(&main, .{ .name = "main" });
        if (@import("builtin").os.tag == .windows) {
            @export(&__main, .{ .name = "__main" });
        }
    }
}

fn __main() callconv(.c) void {}

fn main(argc: c_int, argv: [*][*:0]u8) callconv(.c) c_int {
    _ = argc;
    _ = argv;
    initEnviron();
    return platform_main();
}

// Roc types
const RocStr = builtins.str.RocStr;
const RocList = builtins.list.RocList;

// ============================================================================
// WebSocket Server Implementation
// ============================================================================

const WebSocketOpcode = enum(u4) {
    continuation = 0x0,
    text = 0x1,
    binary = 0x2,
    close = 0x8,
    ping = 0x9,
    pong = 0xA,
};

const WebSocketClient = struct {
    id: u64,
    stream: std.net.Stream,
    is_websocket: bool = false,
    is_closed: bool = false,
};

const WebSocketEvent = union(enum) {
    connected: u64,
    disconnected: u64,
    message: struct { client_id: u64, text: []const u8 },
    err: []const u8,
    shutdown: void,
};

const WebSocketServer = struct {
    allocator: std.mem.Allocator,
    listener: ?std.net.Server,
    clients: std.AutoHashMap(u64, WebSocketClient),
    next_client_id: u64,
    event_queue: std.ArrayListUnmanaged(WebSocketEvent),
    is_running: bool,
    static_dir: ?[]const u8,

    fn init(allocator: std.mem.Allocator) WebSocketServer {
        return .{
            .allocator = allocator,
            .listener = null,
            .clients = std.AutoHashMap(u64, WebSocketClient).init(allocator),
            .next_client_id = 1,
            .event_queue = .{},
            .is_running = false,
            .static_dir = null,
        };
    }

    fn deinit(self: *WebSocketServer) void {
        if (self.listener) |*l| {
            l.deinit();
        }

        var it = self.clients.valueIterator();
        while (it.next()) |client| {
            client.stream.close();
        }
        self.clients.deinit();
        self.event_queue.deinit(self.allocator);
    }

    fn listen(self: *WebSocketServer, port: u16) !void {
        const address = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, port);
        self.listener = try address.listen(.{
            .reuse_address = true,
        });
        self.is_running = true;
        self.static_dir = "static";
    }

    fn accept(self: *WebSocketServer) !WebSocketEvent {
        while (true) {
            // First check event queue
            if (self.event_queue.items.len > 0) {
                return self.event_queue.orderedRemove(0);
            }

            if (!self.is_running) {
                return .shutdown;
            }

            var listener = &(self.listener.?);

            // Set up poll to check for new connections and client data
            var poll_fds = std.ArrayListUnmanaged(std.posix.pollfd){};
            defer poll_fds.deinit(self.allocator);

            // Add listener socket
            try poll_fds.append(self.allocator, .{
                .fd = listener.stream.handle,
                .events = std.posix.POLL.IN,
                .revents = 0,
            });

            // Add all client sockets
            var client_ids = std.ArrayListUnmanaged(u64){};
            defer client_ids.deinit(self.allocator);

            var it = self.clients.iterator();
            while (it.next()) |entry| {
                if (!entry.value_ptr.is_closed) {
                    try poll_fds.append(self.allocator, .{
                        .fd = entry.value_ptr.stream.handle,
                        .events = std.posix.POLL.IN,
                        .revents = 0,
                    });
                    try client_ids.append(self.allocator, entry.key_ptr.*);
                }
            }

            const dbg = std.fs.File.stderr();

            // Poll with longer timeout (5 seconds) to avoid busy spinning
            const ready = std.posix.poll(poll_fds.items, 5000) catch |err| {
                const msg = std.fmt.allocPrint(self.allocator, "Poll error: {}", .{err}) catch "Poll error";
                return .{ .err = msg };
            };

            if (ready == 0) {
                // Timeout - just continue polling, don't return an error
                dbg.writeAll(".") catch {};
                continue;
            }

            dbg.writeAll("\n=== Poll ready ===\n") catch {};

            // Check listener for new connections
            if (poll_fds.items[0].revents & std.posix.POLL.IN != 0) {
                dbg.writeAll("=== Connection incoming ===\n") catch {};
                const connection = listener.accept() catch |err| {
                    const msg = std.fmt.allocPrint(self.allocator, "Accept error: {}", .{err}) catch "Accept error";
                    return .{ .err = msg };
                };

                const client_id = self.next_client_id;
                self.next_client_id += 1;

                try self.clients.put(client_id, .{
                    .id = client_id,
                    .stream = connection.stream,
                    .is_websocket = false,
                });

                // Handle HTTP upgrade in a separate step
                if (self.handleNewConnection(client_id)) |event| {
                    return event;
                } else |_| {
                    // Connection handling failed, remove client
                    if (self.clients.fetchRemove(client_id)) |kv| {
                        kv.value.stream.close();
                    }
                }
            }

            // Check clients for incoming data
            for (poll_fds.items[1..], 0..) |pfd, i| {
                if (pfd.revents & std.posix.POLL.IN != 0) {
                    const client_id = client_ids.items[i];
                    if (self.handleClientData(client_id)) |event| {
                        return event;
                    } else |_| {
                        // Error reading, client disconnected
                        if (self.clients.fetchRemove(client_id)) |kv| {
                            kv.value.stream.close();
                        }
                        return .{ .disconnected = client_id };
                    }
                }

                if (pfd.revents & (std.posix.POLL.HUP | std.posix.POLL.ERR) != 0) {
                    const client_id = client_ids.items[i];
                    if (self.clients.fetchRemove(client_id)) |kv| {
                        kv.value.stream.close();
                    }
                    return .{ .disconnected = client_id };
                }
            }
            // No events this poll cycle, continue waiting
        }
    }

    fn handleNewConnection(self: *WebSocketServer, client_id: u64) !WebSocketEvent {
        const client = self.clients.getPtr(client_id) orelse return error.ClientNotFound;

        var buf: [4096]u8 = undefined;
        const n = try client.stream.read(&buf);
        if (n == 0) return error.ConnectionClosed;

        const request = buf[0..n];

        // Parse HTTP request
        if (std.mem.indexOf(u8, request, "Upgrade: websocket")) |_| {
            // WebSocket upgrade request
            if (try self.handleWebSocketUpgrade(client, request)) {
                client.is_websocket = true;
                return .{ .connected = client_id };
            }
        } else if (std.mem.startsWith(u8, request, "GET ")) {
            // Regular HTTP request - serve static files
            try self.handleHttpRequest(client, request);
            client.is_closed = true;
        }

        return error.NotWebSocket;
    }

    fn handleWebSocketUpgrade(self: *WebSocketServer, client: *WebSocketClient, request: []const u8) !bool {
        _ = self;

        // Find Sec-WebSocket-Key
        const key_header = "Sec-WebSocket-Key: ";
        const key_start = std.mem.indexOf(u8, request, key_header) orelse return false;
        const key_value_start = key_start + key_header.len;
        const key_end = std.mem.indexOfPos(u8, request, key_value_start, "\r\n") orelse return false;
        const key = request[key_value_start..key_end];

        // Compute accept key
        const magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
        var hasher = std.crypto.hash.Sha1.init(.{});
        hasher.update(key);
        hasher.update(magic);
        const hash = hasher.finalResult();

        var accept_key: [28]u8 = undefined;
        _ = std.base64.standard.Encoder.encode(&accept_key, &hash);

        // Send upgrade response
        const response = "HTTP/1.1 101 Switching Protocols\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Accept: ";

        _ = try client.stream.write(response);
        _ = try client.stream.write(&accept_key);
        _ = try client.stream.write("\r\n\r\n");

        return true;
    }

    fn handleHttpRequest(self: *WebSocketServer, client: *WebSocketClient, request: []const u8) !void {
        // Parse path
        const path_start = std.mem.indexOf(u8, request, "GET ") orelse return;
        const path_end = std.mem.indexOfPos(u8, request, path_start + 4, " ") orelse return;
        var path = request[path_start + 4 .. path_end];

        if (std.mem.eql(u8, path, "/")) {
            path = "/index.html";
        }

        // Serve static file
        const static_dir = self.static_dir orelse "static";
        var file_path_buf: [512]u8 = undefined;
        const file_path = std.fmt.bufPrint(&file_path_buf, "{s}{s}", .{ static_dir, path }) catch {
            try self.sendHttpError(client, 500, "Internal Server Error");
            return;
        };

        const file = std.fs.cwd().openFile(file_path, .{}) catch {
            try self.sendHttpError(client, 404, "Not Found");
            return;
        };
        defer file.close();

        const content = file.readToEndAlloc(self.allocator, 1024 * 1024) catch {
            try self.sendHttpError(client, 500, "Internal Server Error");
            return;
        };
        defer self.allocator.free(content);

        // Determine content type
        const content_type = if (std.mem.endsWith(u8, path, ".html"))
            "text/html"
        else if (std.mem.endsWith(u8, path, ".js"))
            "application/javascript"
        else if (std.mem.endsWith(u8, path, ".css"))
            "text/css"
        else
            "application/octet-stream";

        var header_buf: [256]u8 = undefined;
        const header = std.fmt.bufPrint(&header_buf, "HTTP/1.1 200 OK\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{ content_type, content.len }) catch return;

        _ = try client.stream.write(header);
        _ = try client.stream.write(content);
    }

    fn sendHttpError(self: *WebSocketServer, client: *WebSocketClient, code: u16, message: []const u8) !void {
        _ = self;
        var buf: [256]u8 = undefined;
        const response = std.fmt.bufPrint(&buf, "HTTP/1.1 {d} {s}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n", .{ code, message }) catch return;
        _ = try client.stream.write(response);
    }

    fn handleClientData(self: *WebSocketServer, client_id: u64) !WebSocketEvent {
        const client = self.clients.getPtr(client_id) orelse return error.ClientNotFound;

        if (!client.is_websocket) {
            return error.NotWebSocket;
        }

        var header: [14]u8 = undefined;
        const header_read = try client.stream.read(header[0..2]);
        if (header_read < 2) return error.ConnectionClosed;

        const fin = (header[0] & 0x80) != 0;
        _ = fin;
        const opcode: WebSocketOpcode = @enumFromInt(@as(u4, @truncate(header[0] & 0x0F)));
        const masked = (header[1] & 0x80) != 0;
        var payload_len: u64 = header[1] & 0x7F;

        if (payload_len == 126) {
            _ = try client.stream.read(header[2..4]);
            payload_len = std.mem.readInt(u16, header[2..4], .big);
        } else if (payload_len == 127) {
            _ = try client.stream.read(header[2..10]);
            payload_len = std.mem.readInt(u64, header[2..10], .big);
        }

        var mask: [4]u8 = undefined;
        if (masked) {
            _ = try client.stream.read(&mask);
        }

        // Read payload
        if (payload_len > 65536) return error.PayloadTooLarge;
        const payload = try self.allocator.alloc(u8, @intCast(payload_len));

        var total_read: usize = 0;
        while (total_read < payload_len) {
            const read = try client.stream.read(payload[total_read..]);
            if (read == 0) break;
            total_read += read;
        }

        // Unmask
        if (masked) {
            for (payload, 0..) |*byte, i| {
                byte.* ^= mask[i % 4];
            }
        }

        switch (opcode) {
            .text => {
                return .{ .message = .{ .client_id = client_id, .text = payload } };
            },
            .close => {
                client.is_closed = true;
                if (self.clients.fetchRemove(client_id)) |kv| {
                    kv.value.stream.close();
                }
                self.allocator.free(payload);
                return .{ .disconnected = client_id };
            },
            .ping => {
                // Send pong
                try self.sendFrame(client, .pong, payload);
                self.allocator.free(payload);
                return error.ControlFrame;
            },
            .pong => {
                self.allocator.free(payload);
                return error.ControlFrame;
            },
            else => {
                self.allocator.free(payload);
                return error.UnsupportedOpcode;
            },
        }
    }

    fn sendFrame(self: *WebSocketServer, client: *WebSocketClient, opcode: WebSocketOpcode, payload: []const u8) !void {
        _ = self;
        var header: [10]u8 = undefined;
        var header_len: usize = 2;

        header[0] = 0x80 | @as(u8, @intFromEnum(opcode)); // FIN + opcode

        if (payload.len < 126) {
            header[1] = @intCast(payload.len);
        } else if (payload.len <= 65535) {
            header[1] = 126;
            std.mem.writeInt(u16, header[2..4], @intCast(payload.len), .big);
            header_len = 4;
        } else {
            header[1] = 127;
            std.mem.writeInt(u64, header[2..10], payload.len, .big);
            header_len = 10;
        }

        _ = try client.stream.write(header[0..header_len]);
        _ = try client.stream.write(payload);
    }

    fn send(self: *WebSocketServer, client_id: u64, message: []const u8) !void {
        const client = self.clients.getPtr(client_id) orelse return error.ClientNotFound;
        if (client.is_closed) return error.ConnectionClosed;
        try self.sendFrame(client, .text, message);
    }

    fn broadcast(self: *WebSocketServer, message: []const u8) !void {
        var it = self.clients.valueIterator();
        while (it.next()) |client| {
            if (client.is_websocket and !client.is_closed) {
                self.sendFrame(client, .text, message) catch {};
            }
        }
    }

    fn closeClient(self: *WebSocketServer, client_id: u64) void {
        if (self.clients.fetchRemove(client_id)) |kv| {
            // Send close frame
            self.sendFrame(@constCast(&kv.value), .close, "") catch {};
            kv.value.stream.close();
        }
    }
};

// Global server instance
var global_server: ?*WebSocketServer = null;

// ============================================================================
// Hosted Functions
// ============================================================================

fn getAsSlice(roc_str: *const RocStr) []const u8 {
    if (roc_str.len() == 0) return "";
    return roc_str.asSlice();
}

/// WebServer.listen! : U16 => Result({}, Str)
fn hostedWebServerListen(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
    const stderr = std.fs.File.stderr();
    stderr.writeAll("DEBUG hostedWebServerListen called\n") catch {};

    const Result = extern struct {
        payload: RocStr,
        discriminant: u8,
    };

    const Args = extern struct { port: u16 };
    const args: *Args = @ptrCast(@alignCast(args_ptr));
    const result: *Result = @ptrCast(@alignCast(ret_ptr));

    const host: *HostEnv = @ptrCast(@alignCast(ops.env));

    if (host.server) |_| {
        const msg = "Server already running";
        result.payload = RocStr.init(msg.ptr, msg.len, ops);
        result.discriminant = 0; // Err
        stderr.writeAll("DEBUG listen: returning Err (already running)\n") catch {};
        return;
    }

    const server = host.gpa.allocator().create(WebSocketServer) catch {
        const msg = "Failed to allocate server";
        result.payload = RocStr.init(msg.ptr, msg.len, ops);
        result.discriminant = 0;
        stderr.writeAll("DEBUG listen: returning Err (alloc failed)\n") catch {};
        return;
    };
    server.* = WebSocketServer.init(host.gpa.allocator());

    server.listen(args.port) catch |err| {
        const msg = std.fmt.allocPrint(host.gpa.allocator(), "Failed to listen: {}", .{err}) catch "Listen failed";
        result.payload = RocStr.init(msg.ptr, msg.len, ops);
        result.discriminant = 0;
        stderr.writeAll("DEBUG listen: returning Err (listen failed)\n") catch {};
        return;
    };

    host.server = server;
    global_server = server;

    result.payload = RocStr.empty();
    result.discriminant = 1; // Ok
    stderr.writeAll("DEBUG listen: returning Ok\n") catch {};
}

/// WebServer.accept! : () => Event
fn hostedWebServerAccept(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
    const stderr = std.fs.File.stderr();
    stderr.writeAll("DEBUG hostedWebServerAccept called\n") catch {};
    _ = args_ptr;

    // Event union - discriminant first, then payload
    // Alphabetical order for Roc:
    // Connected { clientId : U64 } = 0
    // Disconnected { clientId : U64 } = 1
    // Error { message : Str } = 2
    // Message { clientId : U64, text : Str } = 3
    // Shutdown = 4
    const EventResult = extern struct {
        discriminant: u8,
        _pad1: [7]u8 = undefined, // padding to align payload to 8 bytes
        payload: extern union {
            client_id: u64,
            message: extern struct {
                client_id: u64,
                text: RocStr,
            },
            err_message: RocStr,
        },
    };

    const result: *EventResult = @ptrCast(@alignCast(ret_ptr));
    const host: *HostEnv = @ptrCast(@alignCast(ops.env));

    const server = host.server orelse {
        result.discriminant = 4; // Shutdown
        return;
    };

    while (true) {

        const event = server.accept() catch |err| {
            if (err == error.ControlFrame or err == error.NotWebSocket) {
                stderr.writeAll("DEBUG accept: ControlFrame or NotWebSocket, continuing\n") catch {};
                continue;
            }
            stderr.writeAll("DEBUG accept: got error, returning Error event\n") catch {};
            const msg = std.fmt.allocPrint(server.allocator, "Error: {}", .{err}) catch "Error";
            result.payload.err_message = RocStr.init(msg.ptr, msg.len, ops);
            result.discriminant = 2; // Error
            return;
        };


        switch (event) {
            .connected => |client_id| {
                result.payload.client_id = client_id;
                result.discriminant = 0; // Connected
                stderr.writeAll("DEBUG accept: returning Connected, discriminant=0\n") catch {};
                // Debug: print struct size and raw bytes
                var size_buf: [64]u8 = undefined;
                const size_str = std.fmt.bufPrint(&size_buf, "DEBUG EventResult size={}, payload offset={}, discriminant offset={}\n", .{ @sizeOf(EventResult), @offsetOf(EventResult, "payload"), @offsetOf(EventResult, "discriminant") }) catch "?";
                stderr.writeAll(size_str) catch {};
                const result_bytes = @as([*]const u8, @ptrCast(result))[0..48];
                stderr.writeAll("DEBUG result bytes: ") catch {};
                for (result_bytes) |b| {
                    var buf: [3]u8 = undefined;
                    _ = std.fmt.bufPrint(&buf, "{x:0>2} ", .{b}) catch {};
                    stderr.writeAll(&buf) catch {};
                }
                stderr.writeAll("\n") catch {};
                return;
            },
            .disconnected => |client_id| {
                result.payload.client_id = client_id;
                result.discriminant = 1; // Disconnected
                stderr.writeAll("DEBUG accept: returning Disconnected, discriminant=1\n") catch {};
                return;
            },
            .message => |msg| {
                result.payload.message.client_id = msg.client_id;
                result.payload.message.text = RocStr.init(msg.text.ptr, msg.text.len, ops);
                result.discriminant = 3; // Message
                stderr.writeAll("DEBUG accept: returning Message, discriminant=3\n") catch {};
                return;
            },
            .err => |msg| {
                result.payload.err_message = RocStr.init(msg.ptr, msg.len, ops);
                result.discriminant = 2; // Error
                stderr.writeAll("DEBUG accept: returning Error\n") catch {};
                return;
            },
            .shutdown => {
                result.discriminant = 4; // Shutdown
                stderr.writeAll("DEBUG accept: returning Shutdown, discriminant=4\n") catch {};
                return;
            },
        }
    }
}

/// WebServer.send! : U64, Str => Result({}, Str)
fn hostedWebServerSend(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
    const stderr = std.fs.File.stderr();
    stderr.writeAll("DEBUG hostedWebServerSend called\n") catch {};

    const Result = extern struct {
        payload: RocStr,
        discriminant: u8,
    };

    const Args = extern struct {
        client_id: u64,
        message: RocStr,
    };

    const args: *Args = @ptrCast(@alignCast(args_ptr));
    const result: *Result = @ptrCast(@alignCast(ret_ptr));
    const host: *HostEnv = @ptrCast(@alignCast(ops.env));

    const server = host.server orelse {
        const msg = "Server not running";
        result.payload = RocStr.init(msg.ptr, msg.len, ops);
        result.discriminant = 0;
        return;
    };

    const message = getAsSlice(&args.message);
    server.send(args.client_id, message) catch |err| {
        const msg = std.fmt.allocPrint(server.allocator, "Send failed: {}", .{err}) catch "Send failed";
        result.payload = RocStr.init(msg.ptr, msg.len, ops);
        result.discriminant = 0;
        return;
    };

    result.payload = RocStr.empty();
    result.discriminant = 1; // Ok
}

/// WebServer.broadcast! : Str => Result({}, Str)
fn hostedWebServerBroadcast(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
    const stderr = std.fs.File.stderr();
    stderr.writeAll("DEBUG hostedWebServerBroadcast called\n") catch {};

    const Result = extern struct {
        payload: RocStr,
        discriminant: u8,
    };

    const Args = extern struct {
        message: RocStr,
    };

    const args: *Args = @ptrCast(@alignCast(args_ptr));
    const result: *Result = @ptrCast(@alignCast(ret_ptr));
    const host: *HostEnv = @ptrCast(@alignCast(ops.env));

    const server = host.server orelse {
        const msg = "Server not running";
        result.payload = RocStr.init(msg.ptr, msg.len, ops);
        result.discriminant = 0;
        return;
    };

    const message = getAsSlice(&args.message);
    server.broadcast(message) catch |err| {
        const msg = std.fmt.allocPrint(server.allocator, "Broadcast failed: {}", .{err}) catch "Broadcast failed";
        result.payload = RocStr.init(msg.ptr, msg.len, ops);
        result.discriminant = 0;
        return;
    };

    result.payload = RocStr.empty();
    result.discriminant = 1; // Ok
}

/// WebServer.close! : U64 => {}
fn hostedWebServerClose(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
    _ = ret_ptr;

    const Args = extern struct {
        client_id: u64,
    };

    const args: *Args = @ptrCast(@alignCast(args_ptr));
    const host: *HostEnv = @ptrCast(@alignCast(ops.env));

    if (host.server) |server| {
        server.closeClient(args.client_id);
    }
}

/// Stderr.line! : Str => {}
fn hostedStderrLine(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
    const dbg = std.fs.File.stderr();
    dbg.writeAll("DEBUG hostedStderrLine called\n") catch {};
    _ = ops;
    _ = ret_ptr;

    const Args = extern struct {
        str: RocStr,
    };
    const args: *Args = @ptrCast(@alignCast(args_ptr));
    const str = getAsSlice(&args.str);

    const stderr = std.fs.File.stderr();
    stderr.writeAll(str) catch {};
    stderr.writeAll("\n") catch {};
}

/// Stdout.line! : Str => {}
fn hostedStdoutLine(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
    const dbg = std.fs.File.stderr();
    dbg.writeAll("DEBUG hostedStdoutLine called\n") catch {};
    _ = ops;
    _ = ret_ptr;

    const Args = extern struct {
        str: RocStr,
    };
    const args: *Args = @ptrCast(@alignCast(args_ptr));
    const str = getAsSlice(&args.str);

    const stdout = std.fs.File.stdout();
    stdout.writeAll(str) catch {};
    stdout.writeAll("\n") catch {};
}

/// Array of hosted function pointers, sorted alphabetically by fully-qualified name
const hosted_function_ptrs = [_]builtins.host_abi.HostedFn{
    hostedStderrLine, // Stderr.line! (index 0)
    hostedStdoutLine, // Stdout.line! (index 1)
    hostedWebServerAccept, // WebServer.accept! (index 2)
    hostedWebServerBroadcast, // WebServer.broadcast! (index 3)
    hostedWebServerClose, // WebServer.close! (index 4)
    hostedWebServerSend, // WebServer.send! (index 5) - SWAPPED
    hostedWebServerListen, // WebServer.listen! (index 6) - SWAPPED
};

/// Platform host entrypoint
fn platform_main() c_int {
    var host_env = HostEnv{
        .gpa = std.heap.GeneralPurposeAllocator(.{}){},
        .server = null,
    };

    var roc_ops = builtins.host_abi.RocOps{
        .env = @as(*anyopaque, @ptrCast(&host_env)),
        .roc_alloc = rocAllocFn,
        .roc_dealloc = rocDeallocFn,
        .roc_realloc = rocReallocFn,
        .roc_dbg = rocDbgFn,
        .roc_expect_failed = rocExpectFailedFn,
        .roc_crashed = rocCrashedFn,
        .hosted_fns = .{
            .count = hosted_function_ptrs.len,
            .fns = @ptrCast(@constCast(&hosted_function_ptrs)),
        },
    };

    var exit_code: i32 = -99;
    var empty_arg: u8 = 0;
    roc__main_for_host(&roc_ops, @as(*anyopaque, @ptrCast(&exit_code)), @as(*anyopaque, @ptrCast(&empty_arg)));

    // Cleanup server
    if (host_env.server) |server| {
        server.deinit();
        host_env.gpa.allocator().destroy(server);
    }

    _ = host_env.gpa.deinit();

    if (debug_or_expect_called.load(.acquire) and exit_code == 0) {
        return 1;
    }

    return exit_code;
}
