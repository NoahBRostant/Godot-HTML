extends Control

@onready var requester: HTTPRequest = $HTTPRequest

@onready var from_label: Label = %emailContentFrom
@onready var address_label: Label = %emailContentAddress
@onready var subject_label: Label = %emailContentSubject
@onready var date_label: Label = %emailContentDate
@onready var webview: Node = %HtmlRect

@onready var email_item = preload("res://scenes/mail_item.tscn")

signal emails_loaded(emails: Array)
var current_email: Dictionary = {}

func _ready():
	requester.request("http://127.0.0.1:5000/api/inbox", [], HTTPClient.METHOD_GET)
	requester.request_completed.connect(_on_request_completed)
	webview.visible = true

func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
	if code == 200 and result == HTTPRequest.RESULT_SUCCESS:
		var json_text = body.get_string_from_utf8()
		var json = JSON.new()
		var parse_result = json.parse(json_text)

		if parse_result == OK:
			var emails: Array = json.data

			for child in %emailList.get_children():
				child.queue_free()

			for email in emails:
				var item = email_item.instantiate()

				item.subject = email.get("subject", "")
				var from = email.get("from", "").split(" ", false)
				item.from = from[0] if from.size() > 0 else ""
				item.body = email.get("body", "")
				item.date = email.get("date", "")

				%emailList.add_child(item)

			emails_loaded.emit(emails)
			display_email(emails[0] if emails.size() > 0 else {})
		else:
			print("JSON Error: ", json.get_error_message())

func display_email(email_data: Dictionary):
	current_email = email_data
	var from = email_data.get("from", "").split(" ", false)
	from_label.text = from[0] if from.size() > 0 else ""
	address_label.text = from[1] if from.size() > 1 else ""
	subject_label.text = email_data.get("subject", "")
	date_label.text = email_data.get("date", "")

	var body = email_data.get("body", "")
	var decoded_body = decode_quoted_printable(body)
	var full_html = ""

	if looks_like_html(decoded_body):
		full_html = ensure_full_html(decoded_body)
	else:
		decoded_body = linkify(decoded_body)
		decoded_body = plaintext_to_html(decoded_body)
		full_html = create_email_html(decoded_body)

	webview.html_source = full_html

func decode_quoted_printable(text: String) -> String:
	var normalized = text.replace("=\r\n", "").replace("=\n", "")
	var bytes = PackedByteArray()
	var i = 0
	while i < normalized.length():
		var ch = normalized[i]
		if ch == "=" and i + 2 < normalized.length():
			var hex = normalized.substr(i + 1, 2)
			if hex.is_valid_hex_number():
				bytes.append(int("0x" + hex))
				i += 3
				continue
		bytes.append_array(ch.to_utf8_buffer())
		i += 1
	return bytes.get_string_from_utf8()

func looks_like_html(text: String) -> bool:
	var regex = RegEx.new()
	regex.compile("(?i)<\\s*(html|body|div|table|style|head|meta|p|span|h1|h2|h3)[\\s>]")
	return regex.search(text) != null

func ensure_full_html(body: String) -> String:
	if body.findn("<html") != -1:
		return body
	return create_email_html(body)

func plaintext_to_html(text: String) -> String:
	text = text.replace("\r\n", "\n")
	text = text.replace("\n\n", "</p><p>")
	text = text.replace("\n", "<br>")
	return "<p>" + text + "</p>"

func linkify(text: String) -> String:
	var regex = RegEx.new()
	regex.compile("(https?://[^\\s]+)")
	return regex.sub(text, "<a href=\"$1\">$1</a>", true)

func create_email_html(body: String) -> String:
	return """
	<!DOCTYPE html>
	<html>
	<head>
		<meta charset="UTF-8">
		<style>
			body {
				margin: 0;
				padding: 24px;
				font-family: "Helvetica Neue", Arial, sans-serif;
				line-height: 1.6;
				color: #1F1F1F;
				background-color: #f9f9fb;
			}
			a { color: #6435e9; }
		</style>
	</head>
	<body>
		%s
	</body>
	</html>
	""" % body

func strip_html(html: String) -> String:
	var result = ""
	var in_tag = false
	for i in range(html.length()):
		var char = html[i]
		if char == "<":
			in_tag = true
		elif char == ">" and in_tag:
			in_tag = false
		elif not in_tag:
			result += char
	return result.strip_edges()
