import std.stdio;
import std.format;
import std.file : write, exists, mkdir, rmdirRecurse, read, getSize, dirEntries, SpanMode;
import std.json;
import std.socket;
import std.array;

import std.algorithm : remove, filter, map;

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

// the origin of the frontend to allow it through CORS
__gshared string frontend_origin;

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

void notify_about_images(WebSocket sock, string user_id) {
    string[] images = dirEntries(format("/tmp/qsld_web/%s", user_id), SpanMode.shallow, false)
        .map!(f => f.name)
        .array
        .filter!(f => f.endsWith(".png"))
        .array
        .map!(f => f.split("/")[$ - 1])
        .array;

    if (images.length > 0) {
        string notification_json = format(`
        {
            "contentType": "images",
            "images": %s 
        }
        `, images);

        sock.send(notification_json);
    }
}

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
