WebServer :: [].{
    listen! : U16 => [Ok({}), Err(Str)]
    run! : () => [Ok({}), Err(Str)]
    accept! : () => [Connected(U64), Disconnected(U64), Message(U64, Str), Error(Str), Shutdown]
    send! : U64, Str => [Ok({}), Err(Str)]
    broadcast! : Str => [Ok({}), Err(Str)]
    close! : U64 => {}
}
