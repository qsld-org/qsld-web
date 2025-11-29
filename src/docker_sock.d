#!/usr/bin/env dub
/+ dub.sdl:
   name "websocket_vibed"
   dependency "vibe-d" version="~>0.9.0"
+/

import std.stdio;
import std.array;
import std.socket;

import std.conv : to;
import std.typecons : Tuple, tuple;
import std.string;
import std.algorithm.searching : canFind;
import core.stdc.stdlib : exit;

Socket docker_socket_connect() {
    auto docker_socket = new Socket(AddressFamily.UNIX, SocketType.STREAM);
    string docker_socket_path = "/var/run/docker.sock";
    auto docker_socket_addr = new UnixAddress(docker_socket_path);
    try {
        docker_socket.connect(docker_socket_addr);
        return docker_socket;
    } catch (SocketOSException e) {
        writeln("Could not connect to docker socket: %s", e);
        exit(1);
    }
}

Tuple!(string, char[], long) docker_socket_send_request(Socket docker_socket, string req) {
    docker_socket.send(req);
    char[4096] buffer;
    auto n = docker_socket.receive(buffer);
    string response = cast(string) buffer[0 .. n];
    return tuple(response, buffer[0 .. n], n);
}

string get_and_parse_response(string response, char[] buffer, long n) {
    string[] result = cast(string[]) response.split("\r\n");
    string response_body;
    for (int i = 0; i < result.length; i++) {
        if (result[i].canFind("Content-Length")) {
            string[] result_parts = result[i].split(":");
            int content_length = to!int(strip(result_parts[1]));
            response_body = cast(string) buffer[(n - content_length) .. n];
            break;
        }
    }
    return response_body;
}
