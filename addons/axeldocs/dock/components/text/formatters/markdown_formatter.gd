## Static Markdown-to-BBCode converter used by [DocText].
## Handles inline formatting, headers, code spans, images, links, and custom emoji.
## All transformations produce a new string; the source is never mutated.
class_name MarkdownFormatter


## Number of pixels added to the current font size when sizing inline emoji images.
const EMOJI_SIZE_OFFSET: int = 4

## Default RichTextLabel base font size used for emoji sizing and header scaling.
const BASE_FONT_SIZE: int = 14

## Folder containing the custom emoji images.
const EMOJI_DIR := "res://addons/axeldocs/dock/components/text/custom_emoji"

## Header font sizes for levels h1 through h6 at 100% zoom.
const HEADER_SIZES: Array[int] = [30, 26, 22, 18, 14, 10]

## Compiled regexes cached by pattern, so each pattern is compiled only once.
static var _regex_cache: Dictionary = {}

## Emoji name → resource path, built once on first use.
static var _emoji_paths: Dictionary = {}
static var _emoji_paths_loaded: bool = false


## Returns a compiled (and cached) [RegEx] for [param pattern].
static func _get_regex(pattern: String) -> RegEx:
	var re: RegEx = _regex_cache.get(pattern)
	if re == null:
		re = RegEx.create_from_string(pattern)
		_regex_cache[pattern] = re
	return re


## Returns the resource path of the custom emoji named [param emoji_name],
## or an empty string if it doesn't exist. The directory is scanned only once.
static func _get_emoji_path(emoji_name: String) -> String:
	if not _emoji_paths_loaded or _emoji_paths.is_empty():
		_emoji_paths_loaded = true
		var dir := DirAccess.open(EMOJI_DIR)
		if dir:
			dir.list_dir_begin()
			var file := dir.get_next()
			while file != "":
				if not dir.current_is_dir() and not file.ends_with(".import"):
					_emoji_paths[file.get_basename()] = EMOJI_DIR.path_join(file)
				file = dir.get_next()
			dir.list_dir_end()
	return _emoji_paths.get(emoji_name, "")


## Converts a Markdown string to BBCode ready for use in a [RichTextLabel].
## Protects code spans and link URLs from formatting passes, then restores them
## after all substitutions are complete.
## [param zoom] scales header and emoji font sizes.
static func highlight(source: String, zoom: float = 1.0) -> String:
	var result := source

	# Protect linked inline code: [`code`](url), must run before everything else
	var linked_codes: Array = []
	var linked_code_re := _get_regex(r"\[`([^`]*)`\]\(([^)]+)\)")
	var lc_out := ""
	var lc_last := 0
	for m in linked_code_re.search_all(result):
		lc_out += result.substr(lc_last, m.get_start() - lc_last)
		linked_codes.append({"content": m.get_string(1), "url": m.get_string(2)})
		lc_out += "%%LCODE%d%%" % (linked_codes.size() - 1)
		lc_last = m.get_end()
	lc_out += result.substr(lc_last)
	result = lc_out

	# Preserve code blocks so emojis don't work inside them
	var code_blocks := []
	var code_re := _get_regex(r"\[code\].*?\[/code\]")

	var protected := ""
	var last := 0
	var i := 0

	for m in code_re.search_all(result):
		protected += result.substr(last, m.get_start() - last)

		var token := "%%CB%d%%" % i
		code_blocks.append(m.get_string())
		protected += token

		last = m.get_end()
		i += 1

	protected += result.substr(last)
	result = protected

	# Protect link URLs from bold/italic processing
	var link_urls: Array = []
	var link_url_re := _get_regex(r"(!?\[[^\]]*\])\(([^)]+)\)")
	var link_out := ""
	var link_last := 0
	for lm in link_url_re.search_all(result):
		link_out += result.substr(link_last, lm.get_start() - link_last)
		var ltoken := "%%LURL%d%%" % link_urls.size()
		link_urls.append(lm.get_string(2))
		link_out += lm.get_string(1) + "(" + ltoken + ")"
		link_last = lm.get_end()
	link_out += result.substr(link_last)
	result = link_out

	# Convert inline backtick code spans BEFORE bold/italic processing so that
	# underscores inside backticks are never treated as italic markers.
	result = _re_replace(result, r"`([^`]*)`", " [code]$1[/code] ")
	result = _re_replace(result, r"(?m)^ \[code\]", "[code]")
	result = _re_replace(result, r"(?m)\[/code\] $", "[/code]")

	# Protect those new [code] spans so the bold/italic and emoji passes skip them.
	var protected2 := ""
	var last2 := 0
	for m in code_re.search_all(result):
		protected2 += result.substr(last2, m.get_start() - last2)
		var token := "%%CB%d%%" % code_blocks.size()
		code_blocks.append(m.get_string())
		protected2 += token
		last2 = m.get_end()
	protected2 += result.substr(last2)
	result = protected2

	# Bold-italic
	result = _re_replace(result, r"\*\*\*(.*?)\*\*\*", "[b][i]$1[/i][/b]")
	result = _re_replace(result, r"___(.*?)___",        "[b][i]$1[/i][/b]")

	# Bold
	result = _re_replace(result, r"\*\*(.*?)\*\*", "[b]$1[/b]")
	result = _re_replace(result, r"__(.*?)__",     "[b]$1[/b]")

	# Italic
	result = _re_replace(result, r"\*(.*?)\*", "[i]$1[/i]")
	result = _re_replace(result, r"_(.*?)_",   "[i]$1[/i]")

	# Strikethrough
	result = _re_replace(result, r"~~(.*?)~~", "[s]$1[/s]")

	# Headers FIRST so emojis know the current font size
	for level in HEADER_SIZES.size():
		var size := maxi(1, roundi(HEADER_SIZES[level] * zoom))
		result = _re_replace(
			result,
			r"(?m)^#{%d}\s+(.*?)$" % (level + 1),
			"[font_size=%d][b]$1[/b][/font_size]" % size
		)

	# Emojis with dynamic font size
	var emoji_re := _get_regex(r":([a-zA-Z0-9_\-]+):")

	var out := ""
	last = 0

	for m in emoji_re.search_all(result):
		out += result.substr(last, m.get_start() - last)

		var before := result.substr(0, m.get_start())

		# Default RichTextLabel font size (scaled by zoom)
		var font_size := maxi(1, roundi(BASE_FONT_SIZE * zoom)) + EMOJI_SIZE_OFFSET

		# Find latest active font_size tag
		var size_re := _get_regex(r"\[font_size=(\d+)\]")

		for s in size_re.search_all(before):
			font_size = int(s.get_string(1)) + EMOJI_SIZE_OFFSET

		var emoji_name := m.get_string(1)
		var found_path := _get_emoji_path(emoji_name)

		if found_path != "":
			out += "[img=%dem]%s[/img]" % [
				font_size,
				found_path
			]
		else:
			out += m.get_string()

		last = m.get_end()

	out += result.substr(last)
	result = out

	# Restore link URLs
	for j in link_urls.size():
		result = result.replace("%%LURL%d%%" % j, link_urls[j])

	# Internal anchor link
	result = _re_replace(
		result,
		r"\[([^\]]+)\]\(#([^)]+)\)",
		"[url=anchor:$2]$1[/url]"
	)

	# Cross-page anchor link
	result = _re_replace(
		result,
		r"\[([^\]]+)\]\(([^)#]+\.md)#([^)]+)\)",
		"[url=pageanchor:$2#$3]$1[/url]"
	)

	# Cross-page link (no anchor)
	result = _re_replace(
		result,
		r"\[([^\]]+)\]\(([^)#]+\.md)\)",
		"[url=classpage:$2]$1[/url]"
	)

	# External link
	result = _re_replace(
		result,
		r"\[([^\]]+)\]\(([^)]+)\)",
		"[url=$2]$1[/url]"
	)
	
	# Restore code blocks
	for j in code_blocks.size():
		result = result.replace(
			"%%CB%d%%" % j,
			code_blocks[j]
		)

	# Restore linked inline code as special tags for GDScriptFormatter
	for j in linked_codes.size():
		var lc: Dictionary = linked_codes[j]
		result = result.replace(
			"%%LCODE%d%%" % j,
			" [code=EXPURL:%s]%s[/code] " % [lc["url"], lc["content"]]
		)

	result = result.replace(char(1), "[lb]")
	return result


## Converts a heading string into a lowercase, hyphen-separated URL anchor slug.
## Strips leading and trailing hyphens and collapses consecutive hyphens.
static func anchor_slugify(text: String) -> String:
	var s := text.to_lower()

	# replace everything not alphanumeric with hyphens
	var re := _get_regex("[^a-z0-9]+")

	s = re.sub(s, "-", true)

	# cleanup repeated / edge hyphens
	s = s.trim_prefix("-")
	s = s.trim_suffix("-")

	while s.find("--") != -1:
		s = s.replace("--", "-")

	return s


## Applies [param pattern] to [param text] and replaces each match with [param replacement].
## Supports [code]$1[/code] through [code]$N[/code] capture group references.
static func _re_replace(text: String, pattern: String, replacement: String) -> String:
	var re := _get_regex(pattern)

	var out  := ""
	var last := 0

	for m in re.search_all(text):
		out += text.substr(last, m.get_start() - last)

		var rep := replacement

		for g in range(1, m.get_group_count() + 1):
			rep = rep.replace("$%d" % g, m.get_string(g))

		out += rep
		last = m.get_end()

	out += text.substr(last)

	return out
