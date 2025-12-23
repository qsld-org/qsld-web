#!/usr/bin/env dub
/+ dub.sdl:
   name "websocket_vibed"
   dependency "vibe-d" version="~>0.9.0"
+/

import std.stdio : writeln;
import std.socket;
import std.json;
import std.getopt;
import std.algorithm : filter, map, canFind;
import std.process;
import std.array;

import core.stdc.stdlib : exit;

import std.file : write, exists, mkdir, isDir, remove, rmdirRecurse, read, getSize, dirEntries, SpanMode;
import std.conv : to;

import docker_sock;
import lib;
import vibe.vibe;

bool cleanup_flag = false;

void get_and_send_image_file(HTTPServerRequest req, HTTPServerResponse res) {
    enforceHTTP("userid" in req.params, HTTPStatus.badRequest, "Missing user id in request");
    enforceHTTP("file" in req.params, HTTPStatus.badRequest, "Missing image file name in request");

    string user_id = req.params["userid"];
    string filename = req.params["file"];

    enforceHTTP(user_id in user_sessions, HTTPStatus.badRequest, "the user id does not exist");
    enforceHTTP(!filename.canFind("..") && !filename.canFind("/"), HTTPStatus.badRequest, "filename should not be a path or is invalid");

    string image_file_path = format("/tmp/qsld_web/%s/%s", user_id, filename);
    if (!exists(image_file_path)) {
        enforceHTTP(false, HTTPStatus.badRequest, "the image file does not exist");
    }

    FileStream file_stream = openFile(image_file_path, FileMode.read);
    scope (exit) {
        file_stream.close();
    }

    frontend_origin = environment.get("QSLD_WEB_FRONTEND_ORIGIN", "http://localhost:8000");

    res.contentType = "image/png";
    res.headers["Access-Control-Allow-Origin"] = frontend_origin;

    res.writeRawBody(file_stream);
}

void handleConn(scope WebSocket sock) {
    string user_id = get_user_id(sock);
    handleConn_impl(sock, user_id);
}

void handleConn_impl(WebSocket sock, string user_id) {
    admission_mutex = new TaskMutex;
    admission_mutex.lock();
    if (user_id in cleanup_tasks) {
        cleanup_tasks[user_id].interrupt();
        cleanup_tasks.remove(user_id);
    }

    if (!(user_id in users_docker_sockets)) {
        users_docker_sockets[user_id] = docker_socket_connect();
    }

    string docker_container_limit = environment.get("QSLD_WEB_DOCKER_CONTAINER_LIMIT", "15");
    int max_containers = to!int(docker_container_limit);

    string[] docker_containers = docker_container_list_with_label(
        users_docker_sockets[user_id], "managed_by=qsld_web");

    if (docker_containers.length >= max_containers) {
        string limit_msg = "Server is busy, you have been disconnected, please try again later";
        string container_limit_msg = format(`
        {
            "contentType": "notification",
            "type": "busy",
            "notification": "%s" 
        }
        `, limit_msg);

        sock.send(container_limit_msg);
        users_docker_sockets.remove(user_id);
        return;
    }

    if (!(user_id in user_sessions)) {
        user_sessions[user_id] = UserSession(true, false);
    }

    create_user_tmp_dir(user_id);

    if (!(user_id in users_containers) || !docker_container_exists(
            users_docker_sockets[user_id], users_containers[user_id])) {
        users_containers[user_id] = docker_container_create(users_docker_sockets[user_id], user_id);
    }
    admission_mutex.unlock();

    bool is_started = docker_container_is_started(users_docker_sockets[user_id], users_containers[user_id]);
    if (!is_started) {
        docker_container_start(users_docker_sockets[user_id], users_containers[user_id]);
    }

    while (sock.waitForData()) {
        // Recieve the users code
        auto msg = sock.receiveText();
        auto msg_copy = msg;
        runTask({
            try {
                send_running_msg(sock);
                user_sessions[user_id].running = true;

                string[] images = dirEntries(format("/tmp/qsld_web/%s", user_id), SpanMode.shallow, false)
                    .map!(f => f.name)
                    .array
                    .filter!(f => f.endsWith(".png"))
                    .array;

                if (images.length > 0) {
                    foreach (name; images) {
                        remove(name);
                    }
                }

                // Parse the request with the users code
                string code_file_path = format("/tmp/qsld_web/%s/main.d", user_id);
                parse_and_write_user_request(msg_copy, code_file_path);

                // Compile the file with the users code
                string output_file_path = format("/tmp/qsld_web/%s/output.txt", user_id);
                bool compiler_failed = compile_user_code(sock, user_id, output_file_path);

                // Run the users program and send output to frontend
                if (!compiler_failed) {
                    run_user_program(sock, user_id, output_file_path);
                    notify_about_images(sock, user_id);
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
    if (!user_sessions[user_id].connected && !user_sessions[user_id]
        .running) {
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
    router
        .get("/ws", handleWebSockets(&handleConn))
        .get("/artifact/:userid/:file", &get_and_send_image_file);

    listenHTTP("127.0.0.1:8080", router);
    runApplication();
}

void cleanup_cmd() {
    Socket docker_socket = docker_socket_connect();
    string[] container_ids = docker_container_list_with_label(
        docker_socket, "managed_by=qsld_web");
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
