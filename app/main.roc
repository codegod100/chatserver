app [main!] {
    pf: platform "../platform/main.roc",
}

import pf.Stdout
import pf.Stderr
import pf.WebServer
import pf.Json

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
                Ok({}) => Stdout.line!("Broadcast complete, recursing...")
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
    # Get type once to avoid multiple contains calls
    event_type = Json.get_string(json_str, "type")
    
    if event_type == "connected" {
        client_id = Json.get_number(json_str, "clientId")
        Connected(client_id)
    } else if event_type == "disconnected" {
        client_id = Json.get_number(json_str, "clientId")
        Disconnected(client_id)
    } else if event_type == "message" {
        client_id = Json.get_number(json_str, "clientId")
        text = Json.get_string(json_str, "text")
        Message(client_id, text)
    } else if event_type == "error" {
        err_msg = Json.get_string(json_str, "message")
        Error(err_msg)
    } else if event_type == "shutdown" {
        Shutdown
    } else {
        Unknown
    }
}


