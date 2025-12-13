#!/usr/bin/env dub
/+ dub.sdl:
   name "websocket_vibed"
   dependency "vibe-d" version="~>0.9.0"
+/

import std.stdio : writeln;
import std.socket;
import std.typecons : Tuple;
import std.json;
import std.array : split;

import std.file : write, exists, mkdir, isDir, remove, rmdirRecurse, read, getSize;
import std.algorithm.searching : canFind;

import docker_sock;
import lib;
import vibe.vibe;

// map from user id to cleanup task handle
__gshared Task[string] cleanup_tasks;

// map from user id to container id
__gshared string[string] users_containers;

// map from user id to socket connection handle
__gshared Socket[string] users_sockets;

string prettify_output(string output) {
    string[] output_lines = output.split("\n");
    foreach (i, line; output_lines) {
        output_lines[i] = "<p style='color: #c0caf5; font-size: 18px'>" ~ line ~ "</p>";
    }

    return output_lines.join("\n");
}

void cleanup(string user_id) {
    cleanup_tasks[user_id] = runTask({
        try {
            sleep(dur!("seconds")(7));
            // stop the users container if it is started
            bool started = docker_container_is_started(users_sockets[user_id], users_containers[user_id]);
            if (started) {
                docker_container_stop(users_sockets[user_id], users_containers[user_id]);
            }

            // cleanup user temporary container
            docker_container_remove(users_sockets[user_id], users_containers[user_id]);
            users_containers.remove(user_id);

            // cleanup user directory
            string user_tmp_dir = format("/tmp/qsld_web/%s", user_id);
            if (user_tmp_dir.exists()) {
                rmdirRecurse(user_tmp_dir);
            }

            // cleanup user docker socket connection
            users_sockets.remove(user_id);
            writeln(format("User with user_id: %s closed connection", user_id));
        } catch (Exception e) {
        }
    });
}

void handleConn(scope WebSocket sock) {
    string user_id = get_user_id(sock);
    create_user_tmp_dir(user_id);

    if (user_id in cleanup_tasks) {
        cleanup_tasks[user_id].interrupt();
        cleanup_tasks.remove(user_id);
    }

    if (!(user_id in users_sockets)) {
        users_sockets[user_id] = docker_socket_connect();
    }

    if (!(user_id in users_containers) || !docker_container_exists(users_sockets[user_id], users_containers[user_id])) {
        users_containers[user_id] = docker_container_create(users_sockets[user_id], user_id);
    }

    bool is_started = docker_container_is_started(users_sockets[user_id], users_containers[user_id]);
    if (!is_started) {
        docker_container_start(users_sockets[user_id], users_containers[user_id]);
    }

    while (sock.waitForData()) {
        // Recieve the users code and write it to a file
        auto msg = sock.receiveText();
        JSONValue json = parseJSON(msg);
        string code = json["content"].str();
        string code_file_path = format("/tmp/qsld_web/%s/main.d", user_id);
        write(code_file_path, code);

        // Compile the file with the users code
        string compile_cmd = "dmd -of=/sandbox/main -I/usr/local/include/qsld -L-L/usr/local/lib -L='-lqsld' /sandbox/main.d";
        docker_container_exec(users_sockets[user_id], users_containers[user_id], compile_cmd);
        string output_file_path = format("/tmp/qsld_web/%s/output.txt", user_id);
        if (getSize(output_file_path) != 0) {
            string output = cast(string) read(output_file_path);
            output = prettify_output(output);
            writeln(output);
            sock.send(output);
        }
    }

    cleanup(user_id);
}

void main() {
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
