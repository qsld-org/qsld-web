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

    string id = docker_container_create(docker_socket, "testuserid");
    docker_container_start(docker_socket, id);
    docker_container_exec(docker_socket, id, "ls -la /sandbox");
    docker_container_stop(docker_socket, id);
    docker_container_remove(docker_socket, id);

    auto router = new URLRouter;
    router.get("/ws", handleWebSockets(&handleConn));

    listenHTTP("127.0.0.1:8080", router);

    runApplication();
}
