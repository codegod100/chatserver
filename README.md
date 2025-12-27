# Roc WebSocket Chat Server

A real-time chat server built with Roc (backend) and Elm (frontend), communicating via WebSockets.

## Project Structure

```
chatserver/
├── platform/           # Roc platform with WebSocket support
│   ├── main.roc        # Platform definition
│   ├── host.zig        # Zig host with WebSocket server
│   ├── WebServer.roc   # WebSocket server module
│   ├── Stdout.roc      # Console output
│   ├── Stderr.roc      # Error output
│   └── targets/        # Compiled host libraries
├── app/
│   └── main.roc        # Chat server application
├── frontend/
│   ├── elm.json        # Elm project config
│   └── src/
│       └── Main.elm    # Elm chat frontend
├── static/
│   └── index.html      # HTML wrapper with WebSocket JS
├── build.zig
└── build.zig.zon
```

## Prerequisites

- [Zig](https://ziglang.org/download/) (version 0.15.2 or compatible)
- [Roc](https://www.roc-lang.org/) (nightly build)
- [Elm](https://elm-lang.org/) (version 0.19.1)

## Building

### 1. Build the Zig host library

```bash
cd chatserver
zig build native -Doptimize=ReleaseSafe
```

This compiles the WebSocket server host for your native platform.

### 2. Compile the Elm frontend

```bash
cd frontend
elm make src/Main.elm --optimize --output=../static/elm.js
```

### 3. Build the Roc application

```bash
cd ..
roc build app/main.roc
```

## Running

```bash
./app/main
```

Then open your browser to http://localhost:8080

## How It Works

### Backend (Roc + Zig)

The Roc platform provides a WebSocket server API:

```roc
WebServer := [].{
    listen! : U16 => Result({}, Str),
    accept! : () => Event,
    send! : U64, Str => Result({}, Str),
    broadcast! : Str => Result({}, Str),
    close! : U64 => {},
}

Event : [
    Connected { clientId : U64 },
    Disconnected { clientId : U64 },
    Message { clientId : U64, text : Str },
    Error { message : Str },
    Shutdown,
]
```

The Zig host (`platform/host.zig`) implements:
- HTTP server for static files
- WebSocket protocol (RFC 6455)
- Client connection management
- Message broadcasting

### Frontend (Elm)

The Elm application (`frontend/src/Main.elm`) provides:
- Real-time message display
- Message sending
- Connection status indicator
- Client identification

Communication happens through Elm ports, with JavaScript handling the actual WebSocket connection.

## Quick Start Script

You can use this one-liner to build and run everything:

```bash
cd chatserver && \
zig build native -Doptimize=ReleaseSafe && \
cd frontend && elm make src/Main.elm --optimize --output=../static/elm.js && \
cd .. && roc build app/main.roc && ./app/main
```

## Development

For development, you may want to build without optimizations:

```bash
zig build native
```

And compile Elm in debug mode:

```bash
elm make src/Main.elm --output=../static/elm.js
```

## Architecture

```
┌─────────────────┐       WebSocket        ┌─────────────────┐
│   Elm Frontend  │ ◄───────────────────► │   Roc Backend   │
│                 │                        │                 │
│  - Chat UI      │                        │  - Event loop   │
│  - Ports (JS)   │                        │  - Broadcasting │
│  - Messages     │                        │  - JSON msgs    │
└─────────────────┘                        └─────────────────┘
                                                   │
                                                   ▼
                                           ┌─────────────────┐
                                           │   Zig Host      │
                                           │                 │
                                           │  - HTTP server  │
                                           │  - WebSocket    │
                                           │  - Static files │
                                           └─────────────────┘
```

## License

MIT