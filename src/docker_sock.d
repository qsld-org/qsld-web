#!/usr/bin/env dub
/+ dub.sdl:
   name "websocket_vibed"
   dependency "vibe-d" version="~>0.9.0"
+/

import std.stdio;
import std.array;
import std.socket;
import std.format;
import std.json;

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
    long sent = 0;
    while (sent < req.length) {
        long n = docker_socket.send(req[sent .. $]);
        if (n <= 0) {
            writeln("sending docker request failed");
            exit(1);
        }
        sent += n;
    }
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

string docker_container_create(Socket docker_socket, string user_id) {
    string request_body = format(`
    {
        "Image": "qsld_web:latest",
        "HostConfig": {
            "Binds": [
                "/tmp/qsld_web/%s:/sandbox:rw"
            ],
            "Memory": 1500000000,
            "MemorySwap": 1500000000,
            "NanoCPUs": 1000000000
        },
        "Tty": true,
        "OpenStdin": true
    }
    `, user_id);

    ulong body_length = request_body.length;
    string request = format("POST /containers/create HTTP/1.1\r\nHost: docker\r\nContent-Type: application/json\r\nContent-Length: %u\r\n\r\n%s", body_length, request_body);

    Tuple!(string, char[], long) response = docker_socket_send_request(docker_socket, request);
    string response_body = get_and_parse_response(response[0], response[1], response[2]);
    string id = "";
    if (response_body.canFind("message")) {
        JSONValue json = parseJSON(response_body);
        writeln(json["message"].str());
    } else {
        JSONValue json = parseJSON(response_body);
        id = json["Id"].str();
    }
    return id;
}

void docker_container_start(Socket docker_socket, string container_id) {
    ulong body_length = 0;
    string request = format("POST /containers/%s/start HTTP/1.1\r\nHost: docker\r\nContent-Type: application/json\r\nContent-Length: %u\r\n\r\n", container_id, body_length);

    Tuple!(string, char[], long) response = docker_socket_send_request(docker_socket, request);
    string response_body = get_and_parse_response(response[0], response[1], response[2]);
    if (response_body.length > 0 && response_body.canFind("message")) {
        JSONValue json = parseJSON(response_body);
        writeln(json["message"].str());
    }
}

void docker_container_exec(Socket docker_socket, string container_id, string command) {
    // request the execution of a command
    string exec_request_body = format(`
    {
        "AttachStdin": false,
        "AttachStdout": true,
        "AttachStderr": true,
        "DetachKeys": "ctrl-p,ctrl-q",
        "Tty": false,
        "Cmd": [
            "/bin/bash", "-c", "%s > /sandbox/output.txt 2>&1"
        ]
    }`, command);

    ulong exec_body_length = exec_request_body.length;
    string exec_request = format("POST /containers/%s/exec HTTP/1.1\r\nHost: docker\r\nContent-Type: application/json\r\nContent-Length: %u\r\n\r\n%s", container_id, exec_body_length, exec_request_body);
    Tuple!(string, char[], long) exec_response = docker_socket_send_request(
        docker_socket, exec_request);
    string exec_response_body = get_and_parse_response(exec_response[0], exec_response[1], exec_response[2]);
    string exec_id = "";
    if (exec_response_body.canFind("message")) {
        JSONValue json = parseJSON(exec_response_body);
        writeln(json["message"].str());
    } else {
        JSONValue json = parseJSON(exec_response_body);
        exec_id = json["Id"].str();
    }

    // start the execution of the command
    string exec_start_request_body = format(`
    {
        "Detach": true,
        "Tty": false
    }`);

    ulong exec_start_body_length = exec_start_request_body.length;
    string exec_start_request = format("POST /exec/%s/start HTTP/1.1\r\nHost: docker\r\nContent-Type: application/json\r\nContent-Length: %u\r\n\r\n%s", exec_id, exec_start_body_length, exec_start_request_body);
    Tuple!(string, char[], long) response = docker_socket_send_request(docker_socket, exec_start_request);
    string response_body = get_and_parse_response(response[0], response[1], response[2]);
    if (response_body.canFind("message")) {
        JSONValue json = parseJSON(response_body);
        writeln(json["message"].str());
    }
}

void docker_container_stop(Socket docker_socket, string container_id) {
    ulong body_length = 0;
    string request = format("POST /containers/%s/stop HTTP/1.1\r\nHost: docker\r\nContent-Type: application/json\r\nCotent-Length: %u\r\n\r\n", container_id, body_length);
    Tuple!(string, char[], long) response = docker_socket_send_request(docker_socket, request);
    string response_body = get_and_parse_response(response[0], response[1], response[2]);
    if (response_body.canFind("message")) {
        JSONValue json = parseJSON(response_body);
        writeln(json["message"].str());
    }
}

void docker_container_remove(Socket docker_socket, string container_id) {
    ulong body_length = 0;
    string request = format("DELETE /containers/%s HTTP/1.1\r\nHost: docker\r\nContent-Type: application/json\r\nContent-Length: %u\r\n\r\n", container_id, body_length);
    Tuple!(string, char[], long) response = docker_socket_send_request(docker_socket, request);
    string response_body = get_and_parse_response(response[0], response[1], response[2]);
    if (response_body.canFind("message")) {
        JSONValue json = parseJSON(response_body);
        writeln(json["message"].str());
    }
}
