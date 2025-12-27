//! WebSocket Chat Server Platform Host (Rust implementation)
//! Implements a WebSocket server for the Roc chat application

use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::{Arc, Mutex};
use std::thread;
use sha1::{Digest, Sha1};
use base64::Engine;

// Roc FFI types - these match the Zig implementation's ABI
#[repr(C)]
pub struct RocStr {
    bytes: *const u8,
    length: usize,
    capacity: usize,
}

impl RocStr {
    pub fn empty() -> Self {
        Self {
            bytes: std::ptr::null(),
            length: 0,
            capacity: 0,
        }
    }

    pub fn init(bytes: *const u8, len: usize, _ops: *const ()) -> Self {
        Self {
            bytes,
            length: len,
            capacity: len,
        }
    }

    pub fn as_slice(&self) -> &[u8] {
        if self.length == 0 {
            return &[];
        }
        unsafe { std::slice::from_raw_parts(self.bytes, self.length) }
    }

    pub fn to_string(&self) -> String {
        String::from_utf8_lossy(self.as_slice()).to_string()
    }
}

// WebSocket server state
pub struct WebSocketServer {
    listener: Option<TcpListener>,
    clients: Arc<Mutex<HashMap<u64, Arc<Mutex<WebSocketClient>>>>>,
    next_client_id: Arc<Mutex<u64>>,
    static_dir: String,
    event_queue: Arc<Mutex<Vec<WebSocketEvent>>>,
}

struct WebSocketClient {
    id: u64,
    stream: TcpStream,
    is_websocket: bool,
    is_closed: bool,
}

#[derive(Debug, Clone)]
pub enum WebSocketEvent {
    Connected(u64),
    Disconnected(u64),
    Message { client_id: u64, text: String },
    Error(String),
    Shutdown,
}

#[repr(u8)]
enum WebSocketOpcode {
    Continuation = 0x0,
    Text = 0x1,
    Binary = 0x2,
    Close = 0x8,
    Ping = 0x9,
    Pong = 0xA,
}

impl WebSocketServer {
    pub fn new() -> Self {
        Self {
            listener: None,
            clients: Arc::new(Mutex::new(HashMap::new())),
            next_client_id: Arc::new(Mutex::new(1)),
            static_dir: "static".to_string(),
            event_queue: Arc::new(Mutex::new(Vec::new())),
        }
    }

    pub fn listen(&mut self, port: u16) -> Result<(), String> {
        let addr = format!("0.0.0.0:{}", port);
        let listener = TcpListener::bind(&addr)
            .map_err(|e| format!("Failed to bind: {}", e))?;
        listener.set_nonblocking(true)
            .map_err(|e| format!("Failed to set nonblocking: {}", e))?;
        self.listener = Some(listener);
        
        // Start background thread to handle connections
        let clients = Arc::clone(&self.clients);
        let next_id = Arc::clone(&self.next_client_id);
        let event_queue = Arc::clone(&self.event_queue);
        let static_dir = self.static_dir.clone();
        let listener_clone = self.listener.as_ref().unwrap().try_clone()
            .map_err(|e| format!("Failed to clone listener: {}", e))?;
        
        thread::spawn(move || {
            Self::connection_handler(listener_clone, clients, next_id, event_queue, static_dir);
        });
        
        Ok(())
    }

    fn connection_handler(
        listener: TcpListener,
        clients: Arc<Mutex<HashMap<u64, Arc<Mutex<WebSocketClient>>>>>,
        next_id: Arc<Mutex<u64>>,
        event_queue: Arc<Mutex<Vec<WebSocketEvent>>>,
        static_dir: String,
    ) {
        loop {
            // Accept new connections (non-blocking)
            match listener.accept() {
                Ok((stream, _)) => {
                    let mut id = next_id.lock().unwrap();
                    let client_id = *id;
                    *id += 1;
                    drop(id);

                    stream.set_nonblocking(true).ok();
                    
                    // Handle the connection in a separate thread
                    let clients_clone = Arc::clone(&clients);
                    let event_queue_clone = Arc::clone(&event_queue);
                    let static_dir_clone = static_dir.clone();
                    
                    thread::spawn(move || {
                        Self::handle_connection(
                            client_id,
                            stream,
                            clients_clone,
                            event_queue_clone,
                            static_dir_clone,
                        );
                    });
                }
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    // No connection ready, check existing clients
                }
                Err(e) => {
                    eprintln!("Accept error: {}", e);
                    thread::sleep(std::time::Duration::from_millis(100));
                    continue;
                }
            }

            // Check existing clients for data
            let mut to_remove = Vec::new();
            {
                let clients_guard = clients.lock().unwrap();
                for (id, client) in clients_guard.iter() {
                    let mut client_guard = client.lock().unwrap();
                    if client_guard.is_closed {
                        to_remove.push(*id);
                        continue;
                    }
                    
                    if client_guard.is_websocket {
                        match Self::try_read_websocket_frame(&mut client_guard.stream) {
                            Ok(Some(frame)) => {
                                match frame {
                                    WebSocketFrame::Text(text) => {
                                        event_queue.lock().unwrap().push(WebSocketEvent::Message {
                                            client_id: *id,
                                            text,
                                        });
                                    }
                                    WebSocketFrame::Close => {
                                        client_guard.is_closed = true;
                                        to_remove.push(*id);
                                        event_queue.lock().unwrap().push(WebSocketEvent::Disconnected(*id));
                                    }
                                    WebSocketFrame::Ping(_) => {
                                        // Send pong
                                        Self::send_frame(&mut client_guard.stream, WebSocketOpcode::Pong, &[]).ok();
                                    }
                                    _ => {}
                                }
                            }
                            Ok(None) => {} // No data ready
                            Err(_) => {
                                client_guard.is_closed = true;
                                to_remove.push(*id);
                                event_queue.lock().unwrap().push(WebSocketEvent::Disconnected(*id));
                            }
                        }
                    }
                }
            }

            // Remove closed clients
            for id in to_remove {
                clients.lock().unwrap().remove(&id);
            }

            // Small sleep to avoid busy-waiting
            thread::sleep(std::time::Duration::from_millis(10));
        }
    }

    fn handle_connection(
        client_id: u64,
        mut stream: TcpStream,
        clients: Arc<Mutex<HashMap<u64, Arc<Mutex<WebSocketClient>>>>>,
        event_queue: Arc<Mutex<Vec<WebSocketEvent>>>,
        static_dir: String,
    ) {
        let mut buffer = [0u8; 4096];
        match stream.read(&mut buffer) {
            Ok(n) if n > 0 => {
                let request = String::from_utf8_lossy(&buffer[..n]);

                if request.contains("Upgrade: websocket") {
                    // WebSocket upgrade request
                    if Self::handle_websocket_upgrade(&mut stream, &request).is_ok() {
                        let client = Arc::new(Mutex::new(WebSocketClient {
                            id: client_id,
                            stream,
                            is_websocket: true,
                            is_closed: false,
                        }));
                        clients.lock().unwrap().insert(client_id, client);
                        event_queue.lock().unwrap().push(WebSocketEvent::Connected(client_id));
                    }
                } else if request.starts_with("GET ") {
                    // Regular HTTP request - serve static files
                    Self::handle_http_request(&mut stream, &request, &static_dir).ok();
                }
            }
            _ => {}
        }
    }

    fn handle_websocket_upgrade(stream: &mut TcpStream, request: &str) -> Result<(), String> {
        // Find Sec-WebSocket-Key
        let key_header = "Sec-WebSocket-Key: ";
        let key_start = request.find(key_header)
            .ok_or_else(|| "No Sec-WebSocket-Key found".to_string())?;
        let key_value_start = key_start + key_header.len();
        let key_end = request[key_value_start..].find("\r\n")
            .ok_or_else(|| "Invalid key format".to_string())?;
        let key = &request[key_value_start..key_value_start + key_end];

        // Compute accept key
        let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
        let mut hasher = Sha1::new();
        hasher.update(key.as_bytes());
        hasher.update(magic.as_bytes());
        let hash = hasher.finalize();

        let accept_key = base64::engine::general_purpose::STANDARD.encode(&hash);

        // Send upgrade response
        let response = format!(
            "HTTP/1.1 101 Switching Protocols\r\n\
             Upgrade: websocket\r\n\
             Connection: Upgrade\r\n\
             Sec-WebSocket-Accept: {}\r\n\r\n",
            accept_key
        );

        stream.write_all(response.as_bytes())
            .map_err(|e| format!("Write error: {}", e))?;

        Ok(())
    }

    fn handle_http_request(stream: &mut TcpStream, request: &str, static_dir: &str) -> Result<(), String> {
        // Parse path
        let path_start = request.find("GET ")
            .ok_or_else(|| "Invalid request".to_string())?;
        let path_end = request[path_start + 4..].find(' ')
            .ok_or_else(|| "Invalid request".to_string())?;
        let mut path = &request[path_start + 4..path_start + 4 + path_end];

        if path == "/" {
            path = "/index.html";
        }

        // Serve static file
        let file_path = format!("{}{}", static_dir, path);
        let content = match std::fs::read(&file_path) {
            Ok(c) => c,
            Err(_) => {
                Self::send_http_error(stream, 404, "Not Found")?;
                return Ok(());
            }
        };

        // Determine content type
        let content_type = if path.ends_with(".html") {
            "text/html"
        } else if path.ends_with(".js") {
            "application/javascript"
        } else if path.ends_with(".css") {
            "text/css"
        } else {
            "application/octet-stream"
        };

        let header = format!(
            "HTTP/1.1 200 OK\r\n\
             Content-Type: {}\r\n\
             Content-Length: {}\r\n\
             Connection: close\r\n\r\n",
            content_type,
            content.len()
        );

        stream.write_all(header.as_bytes())
            .map_err(|e| format!("Write error: {}", e))?;
        stream.write_all(&content)
            .map_err(|e| format!("Write error: {}", e))?;

        Ok(())
    }

    fn send_http_error(stream: &mut TcpStream, code: u16, message: &str) -> Result<(), String> {
        let response = format!(
            "HTTP/1.1 {} {}\r\n\
             Content-Length: 0\r\n\
             Connection: close\r\n\r\n",
            code, message
        );
        stream.write_all(response.as_bytes())
            .map_err(|e| format!("Write error: {}", e))?;
        Ok(())
    }

    pub fn accept(&self) -> Result<WebSocketEvent, String> {
        loop {
            // Check event queue first
            {
                let mut queue = self.event_queue.lock().unwrap();
                if !queue.is_empty() {
                    return Ok(queue.remove(0));
                }
            }

            // Wait a bit before checking again
            thread::sleep(std::time::Duration::from_millis(10));
        }
    }

    pub fn send(&self, client_id: u64, message: &str) -> Result<(), String> {
        let clients = self.clients.lock().unwrap();
        let client = clients.get(&client_id)
            .ok_or_else(|| "Client not found".to_string())?;
        
        let mut client_guard = client.lock().unwrap();
        if client_guard.is_closed {
            return Err("Connection closed".to_string());
        }

        Self::send_frame(&mut client_guard.stream, WebSocketOpcode::Text, message.as_bytes())?;
        Ok(())
    }

    pub fn broadcast(&self, message: &str) -> Result<(), String> {
        let clients = self.clients.lock().unwrap();
        let mut failed_clients = Vec::new();

        for (id, client) in clients.iter() {
            let mut client_guard = client.lock().unwrap();
            if client_guard.is_websocket && !client_guard.is_closed {
                if Self::send_frame(&mut client_guard.stream, WebSocketOpcode::Text, message.as_bytes()).is_err() {
                    failed_clients.push(*id);
                }
            }
        }

        // Remove failed clients
        drop(clients);
        for id in failed_clients {
            self.close_client(id);
        }

        Ok(())
    }

    pub fn close_client(&self, client_id: u64) {
        let mut clients = self.clients.lock().unwrap();
        if let Some(client) = clients.remove(&client_id) {
            let mut client_guard = client.lock().unwrap();
            let _ = Self::send_frame(&mut client_guard.stream, WebSocketOpcode::Close, &[]);
        }
    }

    fn send_frame(stream: &mut TcpStream, opcode: WebSocketOpcode, payload: &[u8]) -> Result<(), String> {
        let mut header = Vec::new();
        
        // FIN + opcode
        header.push(0x80 | opcode as u8);
        
        // Payload length
        if payload.len() < 126 {
            header.push(payload.len() as u8);
        } else if payload.len() <= 65535 {
            header.push(126);
            header.extend_from_slice(&(payload.len() as u16).to_be_bytes());
        } else {
            header.push(127);
            header.extend_from_slice(&(payload.len() as u64).to_be_bytes());
        }

        stream.write_all(&header)
            .map_err(|e| format!("Write error: {}", e))?;
        stream.write_all(payload)
            .map_err(|e| format!("Write error: {}", e))?;

        Ok(())
    }

    fn try_read_websocket_frame(stream: &mut TcpStream) -> Result<Option<WebSocketFrame>, String> {
        let mut header = [0u8; 2];
        match stream.read_exact(&mut header) {
            Ok(_) => {}
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => return Ok(None),
            Err(e) => return Err(format!("Read error: {}", e)),
        }

        let _fin = (header[0] & 0x80) != 0;
        let opcode = header[0] & 0x0F;
        let _masked = (header[1] & 0x80) != 0;
        let mut payload_len = (header[1] & 0x7F) as u64;

        if payload_len == 126 {
            let mut len_bytes = [0u8; 2];
            stream.read_exact(&mut len_bytes)
                .map_err(|e| format!("Read error: {}", e))?;
            payload_len = u16::from_be_bytes(len_bytes) as u64;
        } else if payload_len == 127 {
            let mut len_bytes = [0u8; 8];
            stream.read_exact(&mut len_bytes)
                .map_err(|e| format!("Read error: {}", e))?;
            payload_len = u64::from_be_bytes(len_bytes);
        }

        // Read mask if present (client messages are always masked)
        let mut mask = [0u8; 4];
        stream.read_exact(&mut mask)
            .map_err(|e| format!("Read error: {}", e))?;

        // Read payload
        if payload_len > 65536 {
            return Err("Payload too large".to_string());
        }
        let mut payload = vec![0u8; payload_len as usize];
        stream.read_exact(&mut payload)
            .map_err(|e| format!("Read error: {}", e))?;

        // Unmask
        for (i, byte) in payload.iter_mut().enumerate() {
            *byte ^= mask[i % 4];
        }

        match opcode {
            0x1 => Ok(Some(WebSocketFrame::Text(
                String::from_utf8_lossy(&payload).to_string()
            ))),
            0x8 => Ok(Some(WebSocketFrame::Close)),
            0x9 => Ok(Some(WebSocketFrame::Ping(payload))),
            0xA => Ok(Some(WebSocketFrame::Pong(payload))),
            _ => Err("Unsupported opcode".to_string()),
        }
    }
}

enum WebSocketFrame {
    Text(String),
    Close,
    Ping(Vec<u8>),
    Pong(Vec<u8>),
}

// Global server instance
static mut GLOBAL_SERVER: Option<Box<WebSocketServer>> = None;

// Hosted functions for Roc - these need to match the platform definition
// The exact FFI depends on Roc's Rust runtime, but we'll create a compatible interface

// Helper to create a RocStr from a string (this would normally use Roc's allocator)
fn create_roc_str(s: &str, _ops: *const ()) -> RocStr {
    // In a real implementation, this would allocate using Roc's allocator
    // For now, we'll use a static string approach or leak the memory
    let leaked = Box::leak(s.to_string().into_boxed_str());
    RocStr {
        bytes: leaked.as_ptr(),
        length: leaked.len(),
        capacity: leaked.len(),
    }
}

// WebServer.listen! : U16 => Result({}, Str)
#[no_mangle]
pub extern "C" fn webserver_listen(ops: *const (), ret_ptr: *mut u8, args_ptr: *const u8) {
    unsafe {
        let args: *const u16 = args_ptr as *const u16;
        let port = *args;

        let result: *mut RocResult = ret_ptr as *mut RocResult;

        if GLOBAL_SERVER.is_some() {
            let msg = "Server already running";
            result.as_mut().unwrap().payload = create_roc_str(msg, ops);
            result.as_mut().unwrap().discriminant = 0; // Err
            return;
        }

        let mut server = Box::new(WebSocketServer::new());
        match server.listen(port) {
            Ok(_) => {
                GLOBAL_SERVER = Some(server);
                result.as_mut().unwrap().payload = RocStr::empty();
                result.as_mut().unwrap().discriminant = 1; // Ok
            }
            Err(e) => {
                let msg = format!("Failed to listen: {}", e);
                result.as_mut().unwrap().payload = create_roc_str(&msg, ops);
                result.as_mut().unwrap().discriminant = 0; // Err
            }
        }
    }
}

#[repr(C)]
struct RocResult {
    payload: RocStr,
    discriminant: u8,
}

// WebServer.accept! : () => Str
// Returns a JSON string describing the event
#[no_mangle]
pub extern "C" fn webserver_accept(ops: *const (), ret_ptr: *mut u8, _args_ptr: *const u8) {
    unsafe {
        let result: *mut RocStr = ret_ptr as *mut RocStr;
        
        let server = match &GLOBAL_SERVER {
            Some(s) => s,
            None => {
                // No server running, return shutdown event
                let json = "{\"type\":\"shutdown\"}";
                *result.as_mut().unwrap() = create_roc_str(json, ops);
                return;
            }
        };

        loop {
            match server.accept() {
                Ok(event) => {
                    let json = match event {
                        WebSocketEvent::Connected(client_id) => {
                            format!("{{\"type\":\"connected\",\"clientId\":{}}}", client_id)
                        }
                        WebSocketEvent::Disconnected(client_id) => {
                            format!("{{\"type\":\"disconnected\",\"clientId\":{}}}", client_id)
                        }
                        WebSocketEvent::Message { client_id, text } => {
                            // Escape JSON
                            let escaped = text
                                .replace('\\', "\\\\")
                                .replace('"', "\\\"")
                                .replace('\n', "\\n")
                                .replace('\r', "\\r")
                                .replace('\t', "\\t");
                            format!("{{\"type\":\"message\",\"clientId\":{},\"text\":\"{}\"}}", client_id, escaped)
                        }
                        WebSocketEvent::Error(message) => {
                            let escaped = message
                                .replace('\\', "\\\\")
                                .replace('"', "\\\"");
                            format!("{{\"type\":\"error\",\"message\":\"{}\"}}", escaped)
                        }
                        WebSocketEvent::Shutdown => {
                            "{\"type\":\"shutdown\"}".to_string()
                        }
                    };
                    *result.as_mut().unwrap() = create_roc_str(&json, ops);
                    return;
                }
                Err(e) => {
                    let json = format!("{{\"type\":\"error\",\"message\":\"{}\"}}", e);
                    *result.as_mut().unwrap() = create_roc_str(&json, ops);
                    return;
                }
            }
        }
    }
}

// WebServer.send! : U64, Str => Result({}, Str)
#[no_mangle]
pub extern "C" fn webserver_send(ops: *const (), ret_ptr: *mut u8, args_ptr: *const u8) {
    unsafe {
        #[repr(C)]
        struct Args {
            client_id: u64,
            message: RocStr,
        }
        
        let args: *const Args = args_ptr as *const Args;
        let client_id = (*args).client_id;
        let message_str = (*args).message.to_string();
        
        let result: *mut RocResult = ret_ptr as *mut RocResult;
        
        let server = match &GLOBAL_SERVER {
            Some(s) => s,
            None => {
                let msg = "Server not running";
                result.as_mut().unwrap().payload = create_roc_str(msg, ops);
                result.as_mut().unwrap().discriminant = 0; // Err
                return;
            }
        };

        match server.send(client_id, &message_str) {
            Ok(_) => {
                result.as_mut().unwrap().payload = RocStr::empty();
                result.as_mut().unwrap().discriminant = 1; // Ok
            }
            Err(e) => {
                let msg = format!("Send failed: {}", e);
                result.as_mut().unwrap().payload = create_roc_str(&msg, ops);
                result.as_mut().unwrap().discriminant = 0; // Err
            }
        }
    }
}

// WebServer.broadcast! : Str => Result({}, Str)
#[no_mangle]
pub extern "C" fn webserver_broadcast(ops: *const (), ret_ptr: *mut u8, args_ptr: *const u8) {
    unsafe {
        #[repr(C)]
        struct Args {
            message: RocStr,
        }
        
        let args: *const Args = args_ptr as *const Args;
        let message_str = (*args).message.to_string();
        
        let result: *mut RocResult = ret_ptr as *mut RocResult;
        
        let server = match &GLOBAL_SERVER {
            Some(s) => s,
            None => {
                let msg = "Server not running";
                result.as_mut().unwrap().payload = create_roc_str(msg, ops);
                result.as_mut().unwrap().discriminant = 0; // Err
                return;
            }
        };

        match server.broadcast(&message_str) {
            Ok(_) => {
                result.as_mut().unwrap().payload = RocStr::empty();
                result.as_mut().unwrap().discriminant = 1; // Ok
            }
            Err(e) => {
                let msg = format!("Broadcast failed: {}", e);
                result.as_mut().unwrap().payload = create_roc_str(&msg, ops);
                result.as_mut().unwrap().discriminant = 0; // Err
            }
        }
    }
}

// WebServer.close! : U64 => {}
#[no_mangle]
pub extern "C" fn webserver_close(_ops: *const (), _ret_ptr: *mut u8, args_ptr: *const u8) {
    unsafe {
        let args: *const u64 = args_ptr as *const u64;
        let client_id = *args;
        
        if let Some(server) = &GLOBAL_SERVER {
            server.close_client(client_id);
        }
    }
}

// Stderr.line! : Str => {}
#[no_mangle]
pub extern "C" fn stderr_line(_ops: *const (), _ret_ptr: *mut u8, args_ptr: *const u8) {
    unsafe {
        #[repr(C)]
        struct Args {
            str: RocStr,
        }
        
        let args: *const Args = args_ptr as *const Args;
        let s = (*args).str.to_string();
        
        eprintln!("{}", s);
    }
}

// Stdout.line! : Str => {}
#[no_mangle]
pub extern "C" fn stdout_line(_ops: *const (), _ret_ptr: *mut u8, args_ptr: *const u8) {
    unsafe {
        #[repr(C)]
        struct Args {
            str: RocStr,
        }
        
        let args: *const Args = args_ptr as *const Args;
        let s = (*args).str.to_string();
        
        println!("{}", s);
    }
}

// Note: The actual implementation would need to match Roc's exact FFI calling convention
// This structure provides the necessary functions but may need adjustment based on
// the specific Roc Rust runtime being used
