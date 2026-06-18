#!/usr/bin/env bash
# generic-docs-markdown-scraper.sh
#
# Generic documentation scraper for RAG prep.
#
# What it does:
#   - Prompts the user for a starting documentation URL
#   - Crawls links on the same domain
#   - Optionally limits crawling to the same URL path prefix
#   - Saves one Markdown file per page
#   - Saves one combined Markdown file for RAG ingestion
#
# Output:
#   ./scraped-markdown/
#     index.md
#     install.md
#     getting-started.md
#     ...
#     docs-all.md
#
# Requirements:
#   bash, curl, python3
#
# Optional but recommended:
#   pandoc
#
# Usage:
#   chmod +x generic-docs-markdown-scraper.sh
#   ./generic-docs-markdown-scraper.sh

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

log()  { printf '\033[0;36m[+]\033[0m %s\n' "$*"; }
ok()   { printf '\033[0;32m[✓]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[!]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[0;31m[✗]\033[0m %s\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || err "Missing required command: $1"
}

cleanup() {
  [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
}
trap cleanup EXIT

prompt_default() {
  local prompt="$1"
  local default="$2"
  local answer=""

  read -rp "$prompt [$default]: " answer || true
  if [[ -z "$answer" ]]; then
    echo "$default"
  else
    echo "$answer"
  fi
}

prompt_yes_no() {
  local prompt="$1"
  local default="$2"
  local answer=""

  while true; do
    read -rp "$prompt [$default]: " answer || true
    answer="${answer:-$default}"
    case "${answer,,}" in
      y|yes) echo "yes"; return ;;
      n|no)  echo "no";  return ;;
      *) echo "Enter yes or no." ;;
    esac
  done
}

normalize_url() {
  python3 - "$1" <<'PY'
import sys
from urllib.parse import urlparse, urlunparse

url = sys.argv[1].strip()

if not url:
    raise SystemExit(1)

if "://" not in url:
    url = "https://" + url

p = urlparse(url)

if not p.scheme or not p.netloc:
    raise SystemExit(1)

clean = urlunparse((p.scheme, p.netloc, p.path.rstrip("/") or "/", "", p.query, ""))
print(clean)
PY
}

get_netloc() {
  python3 - "$1" <<'PY'
import sys
from urllib.parse import urlparse
print(urlparse(sys.argv[1]).netloc.lower())
PY
}

get_path_prefix() {
  python3 - "$1" <<'PY'
import sys
from urllib.parse import urlparse

p = urlparse(sys.argv[1])
path = p.path.rstrip("/")
parts = [x for x in path.split("/") if x]

if not parts:
    print("/")
else:
    print("/" + "/".join(parts))
PY
}

slugify_url() {
  python3 - "$1" <<'PY'
import re
import sys
from urllib.parse import urlparse, unquote

url = sys.argv[1].strip()
p = urlparse(url)

path = unquote(p.path).strip("/")
if not path:
    slug = "index"
else:
    slug = path.replace("/", "-")

if p.query:
    query_slug = re.sub(r"[^A-Za-z0-9._-]+", "-", p.query)
    slug = f"{slug}-{query_slug}"

slug = re.sub(r"[^A-Za-z0-9._-]+", "-", slug)
slug = re.sub(r"-+", "-", slug).strip("-").lower()
print(slug or "index")
PY
}

extract_title() {
  python3 - "$1" <<'PY'
import re
import sys
from html import unescape

html_path = sys.argv[1]

with open(html_path, "r", encoding="utf-8", errors="ignore") as f:
    html = f.read()

m = re.search(r"<title[^>]*>(.*?)</title>", html, flags=re.I | re.S)
if m:
    title = re.sub(r"\s+", " ", unescape(m.group(1))).strip()
    print(title)
else:
    print("")
PY
}

discover_links() {
  local html_file="$1"
  local base_url="$2"
  local seed_host="$3"
  local path_prefix="$4"
  local same_path_only="$5"

  python3 - "$html_file" "$base_url" "$seed_host" "$path_prefix" "$same_path_only" <<'PY'
import re
import sys
from urllib.parse import urljoin, urlparse, urlunparse

html_path, base_url, seed_host, path_prefix, same_path_only = sys.argv[1:6]

with open(html_path, "r", encoding="utf-8", errors="ignore") as f:
    html = f.read()

hrefs = re.findall(r'''href\s*=\s*["']([^"']+)["']''', html, flags=re.I)

bad_schemes = ("mailto:", "tel:", "javascript:", "data:")
bad_exts = (
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".ico",
    ".css", ".js", ".zip", ".tar", ".gz", ".tgz", ".7z",
    ".pdf", ".mp4", ".mov", ".avi", ".mp3", ".wav",
    ".deb", ".rpm", ".iso", ".img", ".qcow2", ".vmdk",
)

seen = set()

for href in hrefs:
    href = href.strip()
    if not href or href.startswith("#"):
        continue
    if href.lower().startswith(bad_schemes):
        continue

    url = urljoin(base_url, href)
    p = urlparse(url)

    if p.scheme not in ("http", "https"):
        continue

    if p.netloc.lower() != seed_host:
        continue

    path_lower = p.path.lower()
    if path_lower.endswith(bad_exts):
        continue

    if same_path_only == "yes":
        normalized_prefix = path_prefix.rstrip("/") or "/"
        if normalized_prefix != "/":
            if not (p.path == normalized_prefix or p.path.startswith(normalized_prefix + "/")):
                continue

    clean = urlunparse((p.scheme, p.netloc, p.path.rstrip("/") or "/", "", "", ""))

    if clean not in seen:
        seen.add(clean)
        print(clean)
PY
}

html_to_markdown() {
  local html_file="$1"
  local md_file="$2"
  local url="$3"
  local title="$4"

  if command -v pandoc >/dev/null 2>&1; then
    pandoc \
      --from=html \
      --to=gfm \
      --wrap=none \
      --metadata title="" \
      "$html_file" \
      -o "$md_file.tmp"
  else
    python3 - "$html_file" "$md_file.tmp" <<'PY'
import re
import sys
from html import unescape
from html.parser import HTMLParser

html_path, out_path = sys.argv[1], sys.argv[2]

class MarkdownParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.out = []
        self.skip_stack = []
        self.in_pre = False
        self.in_code = False
        self.list_depth = 0
        self.current_link = None
        self.link_text = []

    def emit(self, text):
        if self.skip_stack:
            return
        if self.current_link is not None:
            self.link_text.append(text)
            return
        self.out.append(text)

    def write(self, text):
        if self.skip_stack:
            return
        text = unescape(text)
        if not self.in_pre:
            text = re.sub(r"\s+", " ", text)
        self.emit(text)

    def newline(self, count=1):
        if self.skip_stack:
            return
        self.emit("\n" * count)

    def handle_starttag(self, tag, attrs):
        tag = tag.lower()
        attrs = dict(attrs)

        if tag in {"script", "style", "nav", "footer", "header", "noscript", "svg", "form"}:
            self.skip_stack.append(tag)
            return

        if self.skip_stack:
            return

        if tag in {"main", "article", "section"}:
            self.newline(2)
        elif tag in {"h1", "h2", "h3", "h4", "h5", "h6"}:
            self.newline(2)
            self.write("#" * int(tag[1]) + " ")
        elif tag == "p":
            self.newline(2)
        elif tag == "br":
            self.newline(1)
        elif tag in {"ul", "ol"}:
            self.list_depth += 1
            self.newline(1)
        elif tag == "li":
            self.newline(1)
            self.write("  " * max(self.list_depth - 1, 0) + "- ")
        elif tag == "pre":
            self.in_pre = True
            self.newline(2)
            self.write("```")
            self.newline(1)
        elif tag == "code":
            if not self.in_pre:
                self.in_code = True
                self.write("`")
        elif tag == "a":
            href = attrs.get("href", "").strip()
            self.current_link = href if href else None
            self.link_text = []
        elif tag in {"strong", "b"}:
            self.write("**")
        elif tag in {"em", "i"}:
            self.write("*")
        elif tag == "blockquote":
            self.newline(2)
            self.write("> ")
        elif tag in {"table", "tr"}:
            self.newline(1)
        elif tag in {"td", "th"}:
            self.write(" | ")

    def handle_endtag(self, tag):
        tag = tag.lower()

        if self.skip_stack:
            if self.skip_stack[-1] == tag:
                self.skip_stack.pop()
            return

        if tag in {"h1", "h2", "h3", "h4", "h5", "h6", "p", "main", "article", "section"}:
            self.newline(2)
        elif tag in {"ul", "ol"}:
            self.list_depth = max(0, self.list_depth - 1)
            self.newline(1)
        elif tag == "pre":
            self.newline(1)
            self.write("```")
            self.newline(2)
            self.in_pre = False
        elif tag == "code":
            if not self.in_pre and self.in_code:
                self.write("`")
                self.in_code = False
        elif tag == "a":
            if self.current_link is not None:
                text = "".join(self.link_text).strip()
                href = self.current_link
                if text:
                    self.out.append(f"[{text}]({href})")
                self.current_link = None
                self.link_text = []
        elif tag in {"strong", "b"}:
            self.write("**")
        elif tag in {"em", "i"}:
            self.write("*")
        elif tag == "blockquote":
            self.newline(2)
        elif tag in {"table", "tr"}:
            self.newline(1)

    def handle_data(self, data):
        if not self.skip_stack:
            self.write(data)

    def handle_entityref(self, name):
        self.write(f"&{name};")

    def handle_charref(self, name):
        self.write(f"&#{name};")

with open(html_path, "r", encoding="utf-8", errors="ignore") as f:
    html = f.read()

# Prefer article/main content over whole page.
for pattern in [
    r"<article\b.*?</article>",
    r"<main\b.*?</main>",
    r'<div[^>]+role=["\']main["\'][^>]*>.*?</div>',
]:
    m = re.search(pattern, html, flags=re.I | re.S)
    if m:
        html = m.group(0)
        break

parser = MarkdownParser()
parser.feed(html)

md = "".join(parser.out)
md = unescape(md)

md = re.sub(r"[ \t]+\n", "\n", md)
md = re.sub(r"\n{4,}", "\n\n\n", md)
md = md.strip() + "\n"

with open(out_path, "w", encoding="utf-8") as f:
    f.write(md)
PY
  fi

  {
    echo "---"
    echo "source: $url"
    if [[ -n "$title" ]]; then
      printf 'title: "%s"\n' "$(printf '%s' "$title" | sed 's/"/\\"/g')"
    fi
    echo "scraper: generic-docs-markdown-scraper"
    echo "---"
    echo
    cat "$md_file.tmp"
  } > "$md_file"

  rm -f "$md_file.tmp"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

clear || true
cat <<'BANNER'
Generic Docs → Markdown Scraper

This tool is intended for documentation you are allowed to copy or ingest.
It writes Markdown files only.
BANNER
echo

need_cmd bash
need_cmd curl
need_cmd python3

if command -v pandoc >/dev/null 2>&1; then
  ok "pandoc found — cleaner Markdown conversion enabled."
else
  warn "pandoc not found — using built-in fallback converter."
  warn "For cleaner Markdown: sudo apt install -y pandoc"
fi
echo

START_URL_RAW=""
while [[ -z "$START_URL_RAW" ]]; do
  read -rp "Starting docs URL: " START_URL_RAW || true
done

START_URL="$(normalize_url "$START_URL_RAW")" || err "Invalid URL: $START_URL_RAW"
SEED_HOST="$(get_netloc "$START_URL")"
PATH_PREFIX="$(get_path_prefix "$START_URL")"

DEFAULT_OUT="$(echo "$SEED_HOST$PATH_PREFIX" | tr '/:' '--' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')-markdown"
OUT_DIR="$(prompt_default "Output folder" "$DEFAULT_OUT")"
MAX_PAGES="$(prompt_default "Maximum pages to scrape" "100")"
DELAY_SECONDS="$(prompt_default "Delay between requests in seconds" "0.25")"
SAME_PATH_ONLY="$(prompt_yes_no "Stay under same URL path prefix: $PATH_PREFIX" "yes")"

[[ "$MAX_PAGES" =~ ^[0-9]+$ ]] || err "Maximum pages must be a number."
(( MAX_PAGES > 0 )) || err "Maximum pages must be greater than zero."

TMP_DIR="$(mktemp -d)"
QUEUE_FILE="$TMP_DIR/queue.txt"
SEEN_FILE="$TMP_DIR/seen.txt"
FAILED_FILE="$TMP_DIR/failed.txt"
COMBINED_FILE="$OUT_DIR/docs-all.md"

mkdir -p "$OUT_DIR"
: > "$QUEUE_FILE"
: > "$SEEN_FILE"
: > "$FAILED_FILE"

echo "$START_URL" >> "$QUEUE_FILE"

log "Start URL:       $START_URL"
log "Domain:          $SEED_HOST"
log "Path prefix:     $PATH_PREFIX"
log "Same path only:  $SAME_PATH_ONLY"
log "Output folder:   $OUT_DIR"
log "Max pages:       $MAX_PAGES"
log "Delay:           ${DELAY_SECONDS}s"
echo

: > "$COMBINED_FILE"
{
  echo "# Scraped Documentation"
  echo
  echo "Start URL: $START_URL"
  echo "Domain: $SEED_HOST"
  echo "Path prefix: $PATH_PREFIX"
  echo
} >> "$COMBINED_FILE"

COUNT=0

while [[ -s "$QUEUE_FILE" && "$COUNT" -lt "$MAX_PAGES" ]]; do
  URL="$(head -n 1 "$QUEUE_FILE")"
  tail -n +2 "$QUEUE_FILE" > "$QUEUE_FILE.tmp" || true
  mv "$QUEUE_FILE.tmp" "$QUEUE_FILE"

  if grep -qxF "$URL" "$SEEN_FILE"; then
    continue
  fi

  echo "$URL" >> "$SEEN_FILE"
  COUNT=$((COUNT + 1))

  SLUG="$(slugify_url "$URL")"
  HTML_FILE="$TMP_DIR/$SLUG.html"
  MD_FILE="$OUT_DIR/$SLUG.md"

  log "[$COUNT/$MAX_PAGES] $URL"

  if ! curl -fsSL \
      --connect-timeout 15 \
      --max-time 60 \
      -A "generic-docs-markdown-scraper/1.0" \
      "$URL" \
      -o "$HTML_FILE"; then
    warn "Failed to fetch: $URL"
    echo "$URL" >> "$FAILED_FILE"
    continue
  fi

  TITLE="$(extract_title "$HTML_FILE")"
  html_to_markdown "$HTML_FILE" "$MD_FILE" "$URL" "$TITLE"
  ok "Saved: $MD_FILE"

  {
    echo
    echo "---"
    echo
    echo "<!-- source: $URL -->"
    echo
    cat "$MD_FILE"
  } >> "$COMBINED_FILE"

  discover_links "$HTML_FILE" "$URL" "$SEED_HOST" "$PATH_PREFIX" "$SAME_PATH_ONLY" \
    | while IFS= read -r NEW_URL; do
        if ! grep -qxF "$NEW_URL" "$SEEN_FILE" && ! grep -qxF "$NEW_URL" "$QUEUE_FILE"; then
          echo "$NEW_URL" >> "$QUEUE_FILE"
        fi
      done

  sleep "$DELAY_SECONDS"
done

echo
ok "Scrape complete."
log "Pages scraped:   $COUNT"
log "Markdown folder: $OUT_DIR"
log "Combined file:   $COMBINED_FILE"

if [[ -s "$FAILED_FILE" ]]; then
  warn "Some pages failed. Failed URL list:"
  cp "$FAILED_FILE" "$OUT_DIR/failed-urls.txt"
  warn "$OUT_DIR/failed-urls.txt"
fi

echo
echo "For RAG, ingest either:"
echo "  $COMBINED_FILE"
echo
echo "or the individual Markdown files:"
echo "  $OUT_DIR/*.md"
