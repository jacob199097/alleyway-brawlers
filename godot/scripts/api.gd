extends Node
## Talks to the game server (backend/). The server is the authority for accounts, currency,
## cards, decks and match rewards; this client only asks it for things and shows the answers.
##
##   var r := await Api.request("GET", "/api/profile/me")
##   if r.ok: print(r.data) else: print(r.error)

const DEFAULT_URL := "https://alleywaybrawlers.duckdns.org"
const TIMEOUT := 10.0
const METHODS := {
	"GET": HTTPClient.METHOD_GET, "POST": HTTPClient.METHOD_POST, "PUT": HTTPClient.METHOD_PUT,
	"PATCH": HTTPClient.METHOD_PATCH, "DELETE": HTTPClient.METHOD_DELETE,
}

var token := ""


func base_url() -> String:
	if Game.server_override != "":
		return Game.server_override.strip_edges().trim_suffix("/")
	return str(Game.settings.get("server_url", DEFAULT_URL)).strip_edges().trim_suffix("/")


## Returns {ok: bool, status: int, data: Variant, error: String}. status 0 = server unreachable.
func request(method: String, path: String, body = null) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	add_child(http)
	var headers := PackedStringArray(["Accept: application/json"])
	if token != "":
		headers.append("Authorization: Bearer " + token)
	var payload := ""
	if body != null or method in ["POST", "PUT", "PATCH"]:
		headers.append("Content-Type: application/json")
		payload = JSON.stringify(body if body != null else {})
	var err := http.request(base_url() + path, headers, METHODS[method], payload)
	if err != OK:
		http.queue_free()
		return _unreachable()
	var res: Array = await http.request_completed   # [result, code, headers, body]
	http.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return _unreachable()
	var code: int = res[1]
	var text: String = res[3].get_string_from_utf8()
	var data = JSON.parse_string(text) if text != "" else null
	var ok := code >= 200 and code < 300
	var error := ""
	if not ok:
		error = str(data.get("error", "")) if data is Dictionary else ""
		if error == "":
			error = "Server error (%d)." % code
	return {"ok": ok, "status": code, "data": data, "error": error}


## Raw bytes from the server (card images, card data). Returns {ok, status, body: PackedByteArray}.
func fetch(path: String, timeout := 30.0) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = timeout
	add_child(http)
	if http.request(base_url() + path) != OK:
		http.queue_free()
		return {"ok": false, "status": 0, "body": PackedByteArray()}
	var res: Array = await http.request_completed
	http.queue_free()
	var ok: bool = res[0] == HTTPRequest.RESULT_SUCCESS and res[1] >= 200 and res[1] < 300
	return {"ok": ok, "status": res[1], "body": res[3]}


func _unreachable() -> Dictionary:
	return {"ok": false, "status": 0, "data": null,
		"error": "Can't reach the server at %s." % base_url()}
