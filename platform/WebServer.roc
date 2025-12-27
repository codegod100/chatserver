WebServer :: [].{
    listen! : U16 => [Ok({}), Err(Str)]
    accept! : () => Str
    send! : U64, Str => [Ok({}), Err(Str)]
    broadcast! : Str => [Ok({}), Err(Str)]
    close! : U64 => {}
}
