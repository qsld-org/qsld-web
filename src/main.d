#!/usr/bin/env dub
/+ dub.sdl:
   name "websocket_vibed"
   dependency "vibe-d" version="~>0.9.0"
+/
import vibe.vibe;
import std.stdio;

void handleConn(scope WebSocket sock) {
	// simple echo server
	while (sock.waitForData()) {
		auto msg = sock.receiveText();
		writeln(msg);
	}
}

void main() {
	auto router = new URLRouter;
	router.get("/ws", handleWebSockets(&handleConn));

	listenHTTP("127.0.0.1:8080", router);

	runApplication();
}
