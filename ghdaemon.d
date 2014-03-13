import std.array;

import ae.net.asockets;
import ae.net.http.responseex;
import ae.net.http.server;
import ae.net.ssl.openssl;

import common;
import queue;

class Web
{
	HttpServer httpd;
	ushort port;

	this()
	{
		httpd = new HttpServer();
		httpd.handleRequest = &onRequest;
		httpd.listen(config.port, config.addr);
	}

	void onRequest(HttpRequest request, HttpServerConnection conn)
	{
		HttpResponseEx resp = new HttpResponseEx();
		
		string resource = request.resource;
		auto segments = resource.split("/")[1..$];
		switch (segments[0])
		{
			case "pull-state.json":
				return conn.sendResponse(resp.serveJson(states));
			default:
				return conn.sendResponse(resp.writeError(HttpStatusCode.NotFound));
		}
	}
}

void main()
{
    new Web();
	nextQueued();
	socketManager.loop();
}
