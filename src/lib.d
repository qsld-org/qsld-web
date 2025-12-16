import std.stdio;
import std.format;
import std.file : write, exists, mkdir, rmdirRecurse, read, getSize;
import std.json;
import std.socket;

import std.algorithm : remove;

import vibe.vibe;

import docker_sock;

struct UserSession {
    bool connected;
    bool running;

    this(bool connected, bool running) {
        this.connected = connected;
        this.running = running;
    }
}

// map from user id to cleanup task handle
__gshared Task[string] cleanup_tasks;

// map from user id to container id
__gshared string[string] users_containers;

// map from user id to docker socket connection handle
__gshared Socket[string] users_docker_sockets;

// map from the user id to the users session
__gshared UserSession[string] user_sessions;

string get_user_id(WebSocket sock) {
    auto ident_msg = sock.receiveText();
    JSONValue ident_json = parseJSON(ident_msg);
    return ident_json["userId"].str();
}

void cleanup(string user_id) {
    cleanup_tasks[user_id] = runTask({
        try {
            sleep(dur!("seconds")(7));

            // stop the users container if it is started
            bool started = docker_container_is_started(users_docker_sockets[user_id], users_containers[user_id]);
            if (started) {
                docker_container_stop(users_docker_sockets[user_id], users_containers[user_id]);
            }

            // cleanup user temporary container
            docker_container_remove(users_docker_sockets[user_id], users_containers[user_id]);
            users_containers.remove(user_id);

            // cleanup user directory
            string user_tmp_dir = format("/tmp/qsld_web/%s", user_id);
            if (user_tmp_dir.exists()) {
                rmdirRecurse(user_tmp_dir);
            }

            // cleanup the connection states
            users_docker_sockets.remove(user_id);
            user_sessions.remove(user_id);
            writeln(format("User with user_id: %s closed connection", user_id));
        } catch (Exception e) {
        }
    });
}

string prettify_output(string output) {
    string[] output_lines = output.split("\n");
    foreach (i, line; output_lines) {
        output_lines[i] = "<p style='color: #c0caf5; font-size: 18px'>" ~ line ~ "</p>";
    }

    return output_lines.join("");
}

void create_user_tmp_dir(string user_id) {
    string file_path = format("/tmp/qsld_web/%s", user_id);
    if (!file_path.exists()) {
        mkdir(file_path);
    }
}
