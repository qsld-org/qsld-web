#!/usr/bin/env dub
/+ dub.sdl:
   name "websocket_vibed"
   dependency "vibe-d" version="~>0.9.0"
+/

import std.stdio;
import std.socket;
import std.typecons : Tuple;
import std.json;
import std.file;
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

    if (!(user_id in users_containers)) {
        users_containers[user_id] = docker_container_create(users_sockets[user_id], user_id);
    }

    while (sock.waitForData()) {
        auto msg = sock.receiveText();
        JSONValue json = parseJSON(msg);
        string code = json["content"].str();
    }

    cleanup_tasks[user_id] = runTask({
        try {
            sleep(dur!("seconds")(7));
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
