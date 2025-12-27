app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
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
            Stdout.line!("Failed to start server: ${msg}")
            return Err(Exit(1))
        }
    }

    Stdout.line!("Waiting for connections...")

    # Event loop
    event_loop!()
}

event_loop! : () => Try({}, [Exit(I32)])
event_loop! = || {
    event = WebServer.accept!()
    Stdout.line!("Event received: ${Str.inspect(event)}")

    match event {
        Connected({ clientId }) => {
            Stdout.line!("Client ${clientId.to_str()} connected")
            welcome_msg = "{\"type\": \"system\", \"text\": \"Welcome to the chat! You are client #${clientId.to_str()}\"}"
            match WebServer.send!(clientId, welcome_msg) {
                Ok({}) => {}
                Err(err) => Stdout.line!("Send error: ${err}")
            }
            # Broadcast join notification
            join_msg = "{\"type\": \"system\", \"text\": \"Client #${clientId.to_str()} joined the chat\"}"
            match WebServer.broadcast!(join_msg) {
                Ok({}) => {}
                Err(err) => Stdout.line!("Broadcast error: ${err}")
            }
            event_loop!()
        }

        Disconnected({ clientId }) => {
            Stdout.line!("Client ${clientId.to_str()} disconnected")
            leave_msg = "{\"type\": \"system\", \"text\": \"Client #${clientId.to_str()} left the chat\"}"
            match WebServer.broadcast!(leave_msg) {
                Ok({}) => {}
                Err(err) => Stdout.line!("Broadcast error: ${err}")
            }
            event_loop!()
        }

        Message({ clientId, text }) => {
            Stdout.line!("Client ${clientId.to_str()}: ${text}")
            # Broadcast the message to all clients
            escaped_text = escape_json_string(text)
            broadcast_msg = "{\"type\": \"message\", \"clientId\": ${clientId.to_str()}, \"text\": ${escaped_text}}"
            match WebServer.broadcast!(broadcast_msg) {
                Ok({}) => {}
                Err(err) => Stdout.line!("Broadcast error: ${err}")
            }
            event_loop!()
        }

        Error({ message }) => {
            Stdout.line!("Error: ${message}")
            event_loop!()
        }

        Shutdown => {
            Stdout.line!("Server shutting down")
            Ok({})
        }

        _ => {
            Stdout.line!("Unknown event received!")
            event_loop!()
        }
    }
}

## Escape a string for JSON (simple implementation)
## Uses for loop to iterate through bytes and escape special characters
escape_json_string : Str -> Str
escape_json_string = |s| {
    bytes = Str.to_utf8(s)
    var $escaped_bytes = []

    for byte in bytes {
        $escaped_bytes = match byte {
            92 => List.concat($escaped_bytes, [92, 92])    # \ -> \\
            34 => List.concat($escaped_bytes, [92, 34])    # " -> \"
            10 => List.concat($escaped_bytes, [92, 110])   # \n -> \n literal
            13 => List.concat($escaped_bytes, [92, 114])   # \r -> \r literal
            9 => List.concat($escaped_bytes, [92, 116])    # \t -> \t literal
            _ => List.append($escaped_bytes, byte)
        }
    }

    escaped =
        match Str.from_utf8($escaped_bytes) {
            Ok(str) => str
            Err(_) => s
        }
    "\"${escaped}\""
}
