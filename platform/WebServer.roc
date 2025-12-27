WebServer := [].{
    listen! : U16 => [Ok({}), Err(Str)],
    accept! : () => Event,
    send! : U64, Str => [Ok({}), Err(Str)],
    broadcast! : Str => [Ok({}), Err(Str)],
    close! : U64 => {},
}

## Events received from the WebSocket server
Event : [
    Connected { clientId : U64 },
    Disconnected { clientId : U64 },
    Message { clientId : U64, text : Str },
    Error { message : Str },
    Shutdown,
]
