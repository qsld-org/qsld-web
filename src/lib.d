import std.format;
import std.file;
import std.json;

import vibe.vibe;

string get_user_id(WebSocket sock) {
    auto ident_msg = sock.receiveText();
    JSONValue ident_json = parseJSON(ident_msg);
    return ident_json["userId"].str();
}

void create_user_tmp_dir(string user_id) {
    string file_path = format("/tmp/qsld_web/%s", user_id);
    if (!file_path.exists()) {
        mkdir(file_path);
    }
}
