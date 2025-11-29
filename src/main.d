#!/usr/bin/env dub
/+ dub.sdl:
   name "websocket_vibed"
   dependency "vibe-d" version="~>0.9.0"
+/

import std.stdio;
import std.socket;
import std.typecons : Tuple;
import docker_sock;
import vibe.vibe;

void handleConn(scope WebSocket sock) {
    // simple echo server
    while (sock.waitForData()) {
        auto msg = sock.receiveText();
        writeln(msg);
    }
}

void main() {
    Socket docker_socket = docker_socket_connect();
    Tuple!(string, char[], long) result = docker_socket_send_request(docker_socket,
        "GET /_ping HTTP/1.1\r\nHost: localhost\r\n\r\n");
    string response_body = get_and_parse_response(result[0], result[1], result[2]);
    writeln(response_body);

    Tuple!(string, char[], long) result1 = docker_socket_send_request(docker_socket,
        "GET /_ping HTTP/1.1\r\nHost: localhost\r\n\r\n");
    string response_body1 = get_and_parse_response(result1[0], result1[1], result1[2]);
    writeln(response_body1);
    auto router = new URLRouter;
    router.get("/ws", handleWebSockets(&handleConn));

    listenHTTP("127.0.0.1:8080", router);

    runApplication();
}
