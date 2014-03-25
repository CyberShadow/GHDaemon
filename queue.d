import core.time;

import std.conv;
import std.digest.md;
import std.file;
import std.functional;
import std.json;
import std.string;

import ae.net.http.client;
import ae.sys.data;
import ae.sys.timing;
import ae.utils.array;
import ae.utils.json;

import common;

void delegate()[] queue;

debug
	enum queueInterval = 1.seconds;
else
	enum queueInterval = 5.seconds;

void nextQueued()
{
	if (!queue.length)
	{
		log("Restarting cycle.");
		foreach (component; components)
			queueComponent(component);
	}
	debug log("Starting next scheduled request.");
	queue.shift()();
}

void scheduleQueue()
{
	debug log("Scheduling next request...");
	setTimeout(toDelegate(&nextQueued), queueInterval);
}

struct State
{
	string state; // pending/success/failure
	string targetUrl;
}

/// states[repo][n]
State[string][string] states;

void queueComponent(string component)
{
	auto repo = component.toLower();
	queue ~=
	{
		githubQuery("https://api.github.com/repos/D-Programming-Language/" ~ repo ~ "/pulls?per_page=100",
			(JSONValue v)
			{
				foreach (pull; v.array)
					(pull)
					{
						auto n = pull["number"].integer.to!string;
						string url = pull["statuses_url"].str ~ "?per_page=100";
						queue ~=
						{
							githubQuery(url,
							(JSONValue v)
							{
								string state = "pending";
								foreach (update; v.array)
									if (update["state"].str != "pending")
									{
										state = update["state"].str;
										break;
									}
								states[repo][n] = State(state, v.array.length ? v[0]["target_url"].str : null);
							});
						};
					}
					(pull);
			}
		);
	};
}

struct CacheEntry
{
	string etag, lastModified, data;
}

bool loadingCache = true;

void githubQuery(string url, void delegate(JSONValue) callback)
{
	auto request = new HttpRequest;
	request.resource = url;
	request.headers["Authorization"] = "token " ~ config.token;

	ubyte[16] hash = md5Of(url);
	auto cacheFileName = "cache/" ~ toHexString(hash);

	CacheEntry cacheEntry;
	if (cacheFileName.exists)
	{
		cacheEntry = jsonParse!CacheEntry(readText(cacheFileName));

		if (loadingCache)
		{
			debug log("Loading cached result.");
			callback(parseJSON(cacheEntry.data));
			if (!queue.length)
			{
				debug log("Done loading cache (complete).");
				loadingCache = false;
			}
			return nextQueued();
		}

		if (cacheEntry.etag)
			request.headers["If-None-Match"] = cacheEntry.etag;
		if (cacheEntry.lastModified)
			request.headers["If-Modified-Since"] = cacheEntry.lastModified;
	}
	else
		if (loadingCache)
		{
			debug log("Done loading cache (incomplete).");
			loadingCache = false;
		}

	httpRequest(request,
		(HttpResponse response, string disconnectReason)
		{
			if (!response)
				log("Error with URL " ~ url ~ ": " ~ disconnectReason);
			else
			{
				string s;
				if (response.status == HttpStatusCode.NotModified)
				{
					debug log("Cache hit");
					s = cacheEntry.data;
					callback(parseJSON(s));
				}
				else
				if (response.status == HttpStatusCode.OK)
				{
					debug log("Cache miss");
					scope(failure) std.stdio.writeln(url);
					scope(failure) std.stdio.writeln(response.headers);
					s = (cast(char[])response.getContent().contents).idup;
					cacheEntry.etag = response.headers.get("ETag", null);
					cacheEntry.lastModified = response.headers.get("Last-Modified", null);
					cacheEntry.data = s;
					write(cacheFileName, toJson(cacheEntry));
					callback(parseJSON(s));
				}
				else
					log("Error with URL " ~ url ~ ": " ~ text(response.status));
			}
			scheduleQueue();
		});
}
