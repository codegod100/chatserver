app [main!] {
    pf: platform "../platform/main.roc",
}

import pf.Stdout
import pf.Stderr
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
            Stderr.line!("Failed to start server: ${msg}")
            return Err(Exit(1))
        }
    }

    Stdout.line!("Waiting for connections...")

    event_loop!({})
}

event_loop! : {} => Try({}, [Exit(I32)])
event_loop! = |{}| {
    event = WebServer.accept!()
    
    match event {
        Connected(client_id) => {
            Stdout.line!("Client ${client_id.to_str()} connected")
            
            # Send welcome message
            welcome = "{\"type\": \"system\", \"text\": \"Welcome to the chat! You are client #${client_id.to_str()}\"}"
            send_result = WebServer.send!(client_id, welcome)
            match send_result { Ok({}) => {} Err(_e) => {} }
            
            # Broadcast join message
            join_msg = "{\"type\": \"system\", \"text\": \"Client #${client_id.to_str()} joined the chat\"}"
            broadcast_result = WebServer.broadcast!(join_msg)
            match broadcast_result { Ok({}) => {} Err(_e) => {} }
            
            event_loop!({})
        }
        
        Disconnected(client_id) => {
            Stdout.line!("Client ${client_id.to_str()} disconnected")
            
            # Broadcast leave message
            leave_msg = "{\"type\": \"system\", \"text\": \"Client #${client_id.to_str()} left the chat\"}"
            broadcast_result = WebServer.broadcast!(leave_msg)
            match broadcast_result { Ok({}) => {} Err(_e) => {} }
            
            event_loop!({})
        }
        
        Message(client_id, text) => {
            Stdout.line!("Client ${client_id.to_str()}: ${text}")
            
            # Broadcast the message to all clients (text passed as-is, frontend handles display)
            broadcast_msg = "{\"type\": \"message\", \"clientId\": ${client_id.to_str()}, \"text\": \"${text}\"}"
            broadcast_result = WebServer.broadcast!(broadcast_msg)
            match broadcast_result { Ok({}) => {} Err(_e) => {} }
            
            event_loop!({})
        }
        
        Error(msg) => {
            Stderr.line!("Error: ${msg}")
            event_loop!({})
        }
        
        Shutdown => {
            Stdout.line!("Server shutting down")
            Ok({})
        }
    }
}

