#!/usr/bin/env dub
/+ dub.sdl:
   name "websocket_vibed"
   dependency "vibe-d" version="~>0.9.0"
+/

import std.stdio : writeln;
import std.socket;
import std.json;
import std.getopt;

import core.stdc.stdlib : exit;

import std.file : write, exists, mkdir, isDir, remove, rmdirRecurse, read, getSize;

import docker_sock;
import lib;
import vibe.vibe;

bool cleanup_flag = false;

void send_running_msg(WebSocket sock) {
    string system_output = prettify_output("Running...please wait");
    string system_output_json = format(`
    {
        "contentType": "message",
        "message": "%s"
    }`, system_output);
    sock.send(system_output_json);
}

void parse_and_write_user_request(string request, string code_file_path) {
    JSONValue json = parseJSON(request);
    string code = json["content"].str();
    write(code_file_path, code);
}

bool compile_user_code(WebSocket sock, string user_id, string output_file_path) {
    bool compiler_failed = false;
    string compile_cmd = "dmd -of=/sandbox/main -I/usr/local/include/qsld -L-L/usr/local/lib -L='-lqsld' /sandbox/main.d";
    docker_container_exec(users_docker_sockets[user_id], users_containers[user_id], compile_cmd);
    if (getSize(output_file_path) != 0) {
        string output = cast(string) read(output_file_path);
        output = prettify_output(output);
        string request_json = format(`
        {
            "contentType": "output", 
            "output": "%s"
        }`, output);
        sock.send(request_json);
        compiler_failed = true;
    }

    return compiler_failed;
}

void run_user_program(WebSocket sock, string user_id, string output_file_path) {
    string run_cmd = "/sandbox/main";
    docker_container_exec(users_docker_sockets[user_id], users_containers[user_id], run_cmd);
    if (getSize(output_file_path) != 0) {
        string output = cast(string) read(output_file_path);
        output = prettify_output(output);
        string request_json = format(`
        {
            "contentType": "output", 
            "output": "%s"
        }`, output);
        sock.send(request_json);
    }
}

void handleConn(scope WebSocket sock) {
    string user_id = get_user_id(sock);
    handleConn_impl(sock, user_id);
}

void handleConn_impl(WebSocket sock, string user_id) {
    if (!(user_id in user_sessions)) {
        user_sessions[user_id] = UserSession(true, false);
    }

    create_user_tmp_dir(user_id);

    if (user_id in cleanup_tasks) {
        cleanup_tasks[user_id].interrupt();
        cleanup_tasks.remove(user_id);
    }

    if (!(user_id in users_docker_sockets)) {
        users_docker_sockets[user_id] = docker_socket_connect();
    }

    if (!(user_id in users_containers) || !docker_container_exists(
            users_docker_sockets[user_id], users_containers[user_id])) {
        users_containers[user_id] = docker_container_create(users_docker_sockets[user_id], user_id);
    }

    bool is_started = docker_container_is_started(users_docker_sockets[user_id], users_containers[user_id]);
    if (!is_started) {
        docker_container_start(users_docker_sockets[user_id], users_containers[user_id]);
    }

    while (sock.waitForData()) {
        // Recieve the users code
        auto msg = sock.receiveText();
        auto msg_copy = msg;

        send_running_msg(sock);
        runTask({
            try {
                user_sessions[user_id].running = true;

                // Parse the request with the users code
                string code_file_path = format("/tmp/qsld_web/%s/main.d", user_id);
                parse_and_write_user_request(msg_copy, code_file_path);

                // Compile the file with the users code
                string output_file_path = format("/tmp/qsld_web/%s/output.txt", user_id);
                bool compiler_failed = compile_user_code(sock, user_id, output_file_path);

                // Run the users program and send output to frontend
                if (!compiler_failed) {
                    run_user_program(sock, user_id, output_file_path);
                }

                user_sessions[user_id].running = false;
                if (!user_sessions[user_id].connected && !user_sessions[user_id].running) {
                    cleanup(user_id);
                }
            } catch (Exception e) {
            }
        });
    }

    user_sessions[user_id].connected = false;
    if (!user_sessions[user_id].connected && !user_sessions[user_id].running) {
        cleanup(user_id);
    }
}

void serve() {
    string file_path = "/tmp/qsld_web";
    if (!file_path.exists()) {
        mkdir(file_path);
    } else if (file_path.exists() && !file_path.isDir()) {
        remove(file_path);
        mkdir(file_path);
    }

    auto router = new URLRouter;
    router.get("/ws", handleWebSockets(&handleConn));

    listenHTTP("127.0.0.1:8080", router);
    runApplication();
}

void cleanup_cmd() {
    Socket docker_socket = docker_socket_connect();
    string[] container_ids = docker_container_list_with_label(docker_socket, "managed_by=qsld_web");
    if (container_ids.length == 0) {
        writeln("No containers to cleanup!");
        exit(0);
    } else {
        foreach (id; container_ids) {
            docker_container_remove(docker_socket, id, true);
        }
    }
}

void main(string[] args) {
    auto help_info = getopt(args,
        "c|cleanup", "cleanup any docker containers leftover after abrupt program termination", &cleanup_flag);

    if (help_info.helpWanted) {
        defaultGetoptPrinter("Qsld_Web", help_info.options);
        exit(0);
    }

    if (!cleanup_flag) {
        serve();
    } else {
        cleanup_cmd();
    }
}
