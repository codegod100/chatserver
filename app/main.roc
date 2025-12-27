app [main!] {
    pf: platform "../platform/main.roc",
}

import pf.Stdout
import pf.Stderr
import pf.WebServer
import Json

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
            Stderr.line!("Failed to start server: ${msg}")
            return Err(Exit(1))
        }
    }

    Stdout.line!("Waiting for connections...")

    event_loop!()
}

event_loop! : () => Try({}, [Exit(I32)])
event_loop! = || {
    json_str = WebServer.accept!()
    Stdout.line!("Event JSON: ${json_str}")

    event = parse_event(json_str)
    Stdout.line!("Parsed event, entering match...")

    match event {
        Connected(client_id) => {
            Stdout.line!("Connected branch, client_id received")
            welcome_msg = "{\"type\": \"system\", \"text\": \"Welcome to the chat! You are client #${client_id.to_str()}\"}"
            match WebServer.send!(client_id, welcome_msg) {
                Ok({}) => {}
                Err(err) => Stdout.line!("Send error: ${err}")
            }
            join_msg = "{\"type\": \"system\", \"text\": \"Client #${client_id.to_str()} joined the chat\"}"
            match WebServer.broadcast!(join_msg) {
                Ok({}) => {}
                Err(err) => Stdout.line!("Broadcast error: ${err}")
            }
            event_loop!()
        }

        Disconnected(client_id) => {
            Stdout.line!("Client ${client_id.to_str()} disconnected")
            leave_msg = "{\"type\": \"system\", \"text\": \"Client #${client_id.to_str()} left the chat\"}"
            match WebServer.broadcast!(leave_msg) {
                Ok({}) => {}
                Err(err) => Stdout.line!("Broadcast error: ${err}")
            }
            event_loop!()
        }

        Message(client_id, text) => {
            Stdout.line!("Client ${client_id.to_str()}: ${text}")
            broadcast_msg = "{\"type\": \"message\", \"clientId\": ${client_id.to_str()}, \"text\": \"${text}\"}"
            match WebServer.broadcast!(broadcast_msg) {
                Ok({}) => {}
                Err(err) => Stdout.line!("Broadcast error: ${err}")
            }
            event_loop!()
        }

        Error(message) => {
            Stdout.line!("Error: ${message}")
            event_loop!()
        }

        Shutdown => {
            Stdout.line!("Server shutting down")
            Ok({})
        }

        Unknown => {
            Stdout.line!("Unknown event received: ${json_str}")
            event_loop!()
        }
    }
}

Event : [
    Connected(U64),
    Disconnected(U64),
    Message(U64, Str),
    Error(Str),
    Shutdown,
    Unknown,
]

parse_event : Str -> Event
parse_event = |json_str| {
    # Simple approach: check for substrings
    if Str.contains(json_str, "\"type\":\"connected\"") or Str.contains(json_str, "\"type\": \"connected\"") {
        # Extract clientId - find the number after "clientId":
        client_id = Json.extract_client_id(json_str)
        Connected(client_id)
    } else if Str.contains(json_str, "\"type\":\"disconnected\"") or Str.contains(json_str, "\"type\": \"disconnected\"") {
        client_id = Json.extract_client_id(json_str)
        Disconnected(client_id)
    } else if Str.contains(json_str, "\"type\":\"message\"") or Str.contains(json_str, "\"type\": \"message\"") {
        client_id = Json.extract_client_id(json_str)
        text = Json.get_string(json_str, "text")
        Message(client_id, text)
    } else if Str.contains(json_str, "\"type\":\"error\"") or Str.contains(json_str, "\"type\": \"error\"") {
        err_msg = Json.get_string(json_str, "message")
        Error(err_msg)
    } else if Str.contains(json_str, "\"type\":\"shutdown\"") or Str.contains(json_str, "\"type\": \"shutdown\"") {
        Shutdown
    } else {
        Unknown
    }
}


