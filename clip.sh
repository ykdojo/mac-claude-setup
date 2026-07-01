#!/usr/bin/env bash
#
# clip - sync the clipboard between this Mac and the box over SSH (text or image).
#
#   clip send   # this Mac's clipboard -> the box's clipboard
#   clip get    # the box's clipboard -> this Mac's clipboard
#
# Images are supported both ways: macOS stores clipboard images as PNG, which we
# ship as a file and set on the other side's pasteboard. This works over plain
# SSH - the box has one shared pasteboard for SSH and GUI sessions - so an image
# sent with `clip send` can be pasted straight into a Claude Code session on the
# box with Ctrl-V (claude reads the box pasteboard; the terminal can't carry
# image bytes through a normal paste).
#
# Config: set IC_BOX to <user>@<host> (shared with the `ic` helper).
#
set -euo pipefail

BOX="${IC_BOX:-yk2@newmacbook.local}"

usage() {
  cat <<'EOF'
clip - sync the clipboard between this Mac and the box over SSH (text or image).

  clip send   this Mac's clipboard -> the box   (images: Ctrl-V into claude to attach)
  clip get    the box's clipboard -> this Mac   (then Cmd-V to paste)
  clip -h     this help

Config: set IC_BOX to <user>@<host> (default: yk2@newmacbook.local).
EOF
}

# True if a `clipboard info` string reports an image representation.
is_image() { printf '%s' "$1" | grep -qE 'PNGf|TIFF|picture'; }

case "${1:-}" in
  send)
    info=$(osascript -e 'clipboard info' 2>/dev/null || true)
    if is_image "$info"; then
      f=$(mktemp)
      osascript -e "set h to (open for access (POSIX file \"$f\") with write permission)" \
                -e 'write (the clipboard as «class PNGf») to h' \
                -e 'close access h' >/dev/null 2>&1
      scp -q "$f" "$BOX:/tmp/.clip.png" \
        && ssh "$BOX" 'osascript -e "set the clipboard to (read (POSIX file \"/tmp/.clip.png\") as «class PNGf»)"'
      rm -f "$f"
      echo "image -> box clipboard (press Ctrl-V in your ic session to attach it to claude)"
    else
      pbpaste | ssh "$BOX" pbcopy
      echo "text -> box clipboard (paste with Cmd-V)"
    fi
    ;;

  get)
    info=$(ssh "$BOX" 'osascript -e "clipboard info"' 2>/dev/null || true)
    if is_image "$info"; then
      ssh "$BOX" 'osascript -e "set h to (open for access (POSIX file \"/tmp/.clip.png\") with write permission)" -e "write (the clipboard as «class PNGf») to h" -e "close access h"' >/dev/null 2>&1
      f=$(mktemp)
      scp -q "$BOX:/tmp/.clip.png" "$f"
      osascript -e "set the clipboard to (read (POSIX file \"$f\") as «class PNGf»)"
      rm -f "$f"
      echo "image <- box clipboard (now on this Mac; Cmd-V to paste)"
    else
      ssh "$BOX" pbpaste | pbcopy
      echo "text <- box clipboard (now on this Mac; Cmd-V to paste)"
    fi
    ;;

  -h|--help|help|"")
    usage
    ;;

  *)
    echo "clip: unknown subcommand '$1' (use: clip send | clip get)" >&2
    exit 1
    ;;
esac
