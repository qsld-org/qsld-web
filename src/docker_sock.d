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
import std.conv;
import std.datetime;
import std.string;
import std.process;
import std.uri;

import std.typecons : Tuple, tuple;
import std.algorithm.searching : canFind;
import core.stdc.stdlib : exit;

Socket docker_socket_connect() {
    auto docker_socket = new Socket(AddressFamily.UNIX, SocketType.STREAM);
    string docker_socket_path = "/var/run/docker.sock";
    auto docker_socket_addr = new UnixAddress(docker_socket_path);
    try {
        docker_socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!("seconds")(2));
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
    char[] full_buffer;

    long n;
    while (true) {
        n = docker_socket.receive(buffer);
        if (n <= 0) {
            break;
        }

        full_buffer ~= buffer[0 .. n];

        if (full_buffer.length >= 5 && full_buffer[$ - 5 .. $] == "\r\n0\r\n\r\n") {
            break;
        }
    }
    string response = cast(string) full_buffer;
    return tuple(response, full_buffer, cast(long) full_buffer.length);
}

string get_and_parse_response(string response, char[] buffer, long n) {
    string[] result = cast(string[]) response.split("\r\n");
    string response_body;

    for (int i = 0; i < result.length; i++) {
        if (result[i].startsWith("Transfer-Encoding") && result[i].canFind("chunked")) {
            auto headerEnd = response.indexOf("\r\n\r\n");
            if (headerEnd < 0)
                return "";

            string chunkData = response[headerEnd + 4 .. $];

            ulong idx = 0;
            while (idx < chunkData.length) {
                auto lineEnd = chunkData.indexOf("\r\n", idx);
                if (lineEnd < 0)
                    break;

                string hexSize = chunkData[idx .. lineEnd];
                int size = parse!int(hexSize, 16);

                if (size == 0)
                    break;

                idx = lineEnd + 2;
                response_body ~= chunkData[idx .. idx + size];

                idx += size + 2;
            }
        }

        if (result[i].startsWith("Content-Length")) {
            string[] result_parts = result[i].split(":");
            int content_length = to!int(strip(result_parts[1]));
            response_body = cast(string) buffer[(n - content_length) .. n];
            break;
        }
    }
    return response_body;
}

string docker_container_create(Socket docker_socket, string user_id) {
    string memory_allocated = environment.get("QSLD_WEB_CONTAINERS_MEMORY", "1.5");
    string cpus = environment.get("QSLD_WEB_CONTAINERS_CPUS", "1");

    int memory_amt = cast(int)(to!float(memory_allocated) * 1_000_000_000);
    int cpu_amt = cast(int)(to!float(cpus) * 1_000_000_000);

    string request_body = format(`
    {
        "Image": "qsld_web:latest",
        "HostConfig": {
            "Binds": [
                "/tmp/qsld_web/%s:/sandbox:rw"
            ],
            "Memory": %d,
            "MemorySwap": %d,
            "NanoCPUs": %d
        },
        "Labels": {
            "managed_by": "qsld_web"
        },
        "Tty": true,
        "OpenStdin": true,
        "WorkingDir": "/sandbox"
    }`, user_id, memory_amt, memory_amt, cpu_amt);

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
    Tuple!(string, char[], long) response = docker_socket_send_request(
        docker_socket, exec_start_request);
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

void docker_container_remove(Socket docker_socket, string container_id, bool force = false) {
    ulong body_length = 0;
    string request = format("DELETE /containers/%s%s HTTP/1.1\r\nHost: docker\r\nContent-Type: application/json\r\nContent-Length: %u\r\n\r\n", container_id, force ? "?force=true" : "", body_length);
    Tuple!(string, char[], long) response = docker_socket_send_request(docker_socket, request);
    string response_body = get_and_parse_response(response[0], response[1], response[2]);
    if (response_body.canFind("message")) {
        JSONValue json = parseJSON(response_body);
        writeln(json["message"].str());
    }
}

bool docker_container_is_started(Socket docker_socket, string container_id) {
    ulong body_length = 0;
    string request = format("GET /containers/%s/json HTTP/1.1\r\nHost: docker\r\nContent-Type: application/json\r\nContent-Length: %u\r\n\r\n", container_id, body_length);
    Tuple!(string, char[], long) response = docker_socket_send_request(docker_socket, request);
    string response_body = get_and_parse_response(response[0], response[1], response[2]);
    JSONValue json = parseJSON(response_body);
    string status = json["State"]["Status"].str();
    if (status != "running") {
        return false;
    }
    return true;
}

bool docker_container_exists(Socket docker_socket, string container_id) {
    ulong body_length = 0;
    string request = format("GET /containers/%s/json HTTP/1.1\r\nHost: docker\r\nContent-Type: application/json\r\nContent-Length: %u\r\n\r\n", container_id, body_length);
    Tuple!(string, char[], long) response = docker_socket_send_request(docker_socket, request);
    string response_body = get_and_parse_response(response[0], response[1], response[2]);
    if (response_body.canFind("message")) {
        return false;
    }

    return true;
}

string[] docker_container_list_with_label(Socket docker_socket, string label) {
    string[] results;
    ulong body_length = 0;

    string request_filter = encodeComponent(format(`{"label": ["%s"]}`, label));
    string request = format("GET /containers/json?filters=%s HTTP/1.1\r\nHost: docker\r\nContent-Type: application/json\r\nContent-Length: %u\r\n\r\n", request_filter, body_length);
    Tuple!(string, char[], long) response = docker_socket_send_request(docker_socket, request);
    string response_body = get_and_parse_response(response[0], response[1], response[2]);

    JSONValue json = parseJSON(response_body);
    if (json.type() == JSONType.ARRAY) {
        JSONValue[] containers = json.array();
        foreach (container; containers) {
            results ~= container["Id"].str();
        }
    } else {
        if (response_body.canFind("message")) {
            writeln(json["message"].str());
        }
        return [];
    }

    return results;
}
