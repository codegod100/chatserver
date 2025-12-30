app [main!] {
    pf: platform "../platform/main.roc",
}

import pf.Stdout
import pf.Stderr
import pf.WebServer

## Chat server that handles WebSocket connections
## and broadcasts messages to all connected clients

## State: parallel lists for client IDs and names
## (Using two lists instead of List of records to work around compiler bugs)

## Parsed user command
Command : [
    Nick(Str),
    Help,
    ListUsers,
    Chat(Str),
]

## Parse a message into a command
parse_command : Str -> Command
parse_command = |text| {
    trimmed = text.trim()
    if trimmed.starts_with("/nick ") {
        Nick(trimmed.drop_prefix("/nick ").trim())
    } else if trimmed == "/help" {
        Help
    } else if trimmed == "/list" {
        ListUsers
    } else {
        Chat(text)
    }
}

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

    # Start event loop with empty state (two parallel lists)
    event_loop!([], [])
}

event_loop! : List(U64), List(Str) => Try({}, [Exit(I32)])
event_loop! = |ids, names| {
    event = WebServer.accept!()
    
    match event {
        Connected(client_id) => {
            default_name = "Guest#${client_id.to_str()}"
            new_ids = ids.append(client_id)
            new_names = names.append(default_name)
            
            Stdout.line!("Client ${client_id.to_str()} connected as ${default_name}")
            
            # Send welcome message
            welcome = "{\"type\": \"system\", \"text\": \"Welcome! You are ${default_name}\"}"
            send_result = WebServer.send!(client_id, welcome)
            match send_result { Ok({}) => {} Err(_e) => {} }
            
            # Broadcast join message
            join_msg = "{\"type\": \"system\", \"text\": \"${default_name} joined\"}"
            broadcast_result = WebServer.broadcast!(join_msg)
            match broadcast_result { Ok({}) => {} Err(_e) => {} }
            
            event_loop!(new_ids, new_names)
        }
        
        Disconnected(client_id) => {
            Stdout.line!("Client ${client_id.to_str()} disconnected")
            
            # Broadcast leave message
            leave_msg = "{\"type\": \"system\", \"text\": \"Client ${client_id.to_str()} left\"}"
            broadcast_result = WebServer.broadcast!(leave_msg)
            match broadcast_result { Ok({}) => {} Err(_e) => {} }
            
            # Just filter the lists inline
            new_ids = filter_ids(ids, client_id)
            new_names = filter_names(ids, names, client_id)
            event_loop!(new_ids, new_names)
        }
        
        Message(client_id, text) => {
            Stdout.line!("Client ${client_id.to_str()}: ${text}")
            
            # Just broadcast for now
            broadcast_msg = "{\"type\": \"message\", \"clientId\": ${client_id.to_str()}, \"text\": \"${text}\"}"
            broadcast_result = WebServer.broadcast!(broadcast_msg)
            match broadcast_result { Ok({}) => {} Err(_e) => {} }
            
            event_loop!(ids, names)
        }
        
        Error(msg) => {
            Stderr.line!("Error: ${msg}")
            event_loop!(ids, names)
        }
        
        Shutdown => {
            Stdout.line!("Server shutting down")
            Ok({})
        }
    }
}

## Filter out a client ID from the ids list
filter_ids : List(U64), U64 -> List(U64)
filter_ids = |ids, client_id| {
    var $result = []
    var $i = 0u64
    while $i < ids.len() {
        match ids.get($i) {
            Ok(id) => {
                if id != client_id {
                    $result = $result.append(id)
                }
            }
            Err(_) => {}
        }
        $i = $i + 1
    }
    $result
}

## Filter names corresponding to removed client
filter_names : List(U64), List(Str), U64 -> List(Str)
filter_names = |ids, names, client_id| {
    var $result = []
    var $i = 0u64
    while $i < ids.len() {
        match ids.get($i) {
            Ok(id) => {
                if id != client_id {
                    match names.get($i) {
                        Ok(name) => { $result = $result.append(name) }
                        Err(_) => {}
                    }
                }
            }
            Err(_) => {}
        }
        $i = $i + 1
    }
    $result
}