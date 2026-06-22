#!/bin/bash
# Copyright 2026
# SPDX-License-Identifier: Apache-2.0
#
# printer-keepalive.sh — the worker. Prints a nozzle keep-alive page to stop an
# idle inkjet's nozzles drying out / clogging, and posts a heads-up notification
# first so whoever's at the machine knows the printer is about to wake.
#
# Inkjet nozzles sit in vertical columns and the carriage sweeps sideways, so a
# full-HEIGHT line drives every nozzle of its colour. Three intensities:
#
#   light   one thin line per channel (C/M/Y/K) — routine, minimal ink
#   medium  a comb of 3 thin lines per channel — a catch-up flush
#   heavy   a solid full-height band per channel, printed twice — a deep flush
#
# Intensity is chosen automatically from how long it's been since the last
# successful print: if the Mac was off/asleep across one or more scheduled runs,
# the gap is long, so a heavier flush is printed to clear any partial drying.
#
# Usage:
#   printer-keepalive.sh                 # auto intensity, notify, print, log
#   printer-keepalive.sh --tier medium   # force light|medium|heavy
#   printer-keepalive.sh --dry [tier]    # build + open the PDF, don't print
#
set -euo pipefail

# --- paths / state (mirrors dsort's ~/Library/Scripts convention) ----------
SCRIPTS="$HOME/Library/Scripts"
PRINTER_FILE="$SCRIPTS/printer_keepalive.printer"     # selected printers, one name per line
INTERVAL_FILE="$SCRIPTS/printer_keepalive.interval"   # schedule seconds
LEAD_FILE="$SCRIPTS/printer_keepalive.lead"           # heads-up lead seconds
NONOTIFY_FLAG="$SCRIPTS/printer_keepalive.nonotify"   # presence = notifications OFF
LASTPRINT_FILE="$SCRIPTS/printer_keepalive.lastprint" # epoch of last good print
HISTORY_FILE="$SCRIPTS/printer_keepalive.history"     # TSV: epoch ISO tier days copies printer job
LOG="$HOME/Library/Logs/printer-keepalive.log"
NOTIFIER="$SCRIPTS/PrinterKeepaliveNotifier.app/Contents/MacOS/applet"

DEFAULT_INTERVAL=1209600   # 14 days
DEFAULT_LEAD=8             # seconds of heads-up before the print starts

# --- small helpers ---------------------------------------------------------
trim() { tr -d ' \t\n\r'; }

# selected printers, one per line. If none chosen, fall back to the system
# default destination so it still works out of the box.
get_printers() {
    if [ -r "$PRINTER_FILE" ] && [ -s "$PRINTER_FILE" ]; then
        grep -vE '^[[:space:]]*$' "$PRINTER_FILE"
    else
        lpstat -d 2>/dev/null | sed -n 's/^system default destination: //p' | head -1
    fi
}
get_interval() {
    local v=""; [ -r "$INTERVAL_FILE" ] && v=$(trim < "$INTERVAL_FILE")
    case "$v" in ''|*[!0-9]*) echo "$DEFAULT_INTERVAL" ;; *) echo "$v" ;; esac
}
get_lead() {
    local v=""; [ -r "$LEAD_FILE" ] && v=$(trim < "$LEAD_FILE")
    case "$v" in ''|*[!0-9]*) echo "$DEFAULT_LEAD" ;; *) echo "$v" ;; esac
}
get_last() {
    local v=""; [ -r "$LASTPRINT_FILE" ] && v=$(trim < "$LASTPRINT_FILE")
    case "$v" in ''|*[!0-9]*) echo 0 ;; *) echo "$v" ;; esac
}
notify_on() { [ ! -e "$NONOTIFY_FLAG" ]; }

# post a notification via the applet (env-var payload, dsort's playbook). Silent
# if muted or the applet isn't installed yet.
notify() {
    notify_on || return 0
    [ -x "$NOTIFIER" ] || return 0
    PKA_TITLE="$1" PKA_BODY="$2" "$NOTIFIER" >/dev/null 2>>"$LOG" || true
}

# resolve a python3 (launchd has a minimal PATH)
PYTHON=""
for c in python3 /usr/bin/python3 "$HOME/.local/bin/python3" /opt/homebrew/bin/python3; do
    if command -v "$c" >/dev/null 2>&1; then PYTHON="$c"; break; fi
done

# --- intensity decision ----------------------------------------------------
# Gap since last print, expressed in whole days (for messages).
days_since() {
    local last now; last=$(get_last); now=$(date +%s)
    [ "$last" -le 0 ] && { echo -1; return; }      # -1 = never printed
    echo $(( (now - last) / 86400 ))
}
# Auto tier from the gap relative to the schedule interval:
#   <= 1.5x interval  -> light   (on schedule)
#   <= 3x interval    -> medium  (missed ~1-2 runs)
#   >  3x interval    -> heavy   (long neglect)
decide_tier() {
    local last now elapsed iv; last=$(get_last); iv=$(get_interval); now=$(date +%s)
    [ "$last" -le 0 ] && { echo light; return; }   # first ever run
    elapsed=$(( now - last ))
    if   [ "$elapsed" -le $(( iv * 3 / 2 )) ]; then echo light
    elif [ "$elapsed" -le $(( iv * 3 ))     ]; then echo medium
    else echo heavy; fi
}

# --- build the keep-alive PDF for a given tier -----------------------------
# build_pdf <tier> <subtitle>  -> echoes the temp PDF path
build_pdf() {
    local tier="$1" subtitle="$2" pdf stub
    stub="$(mktemp -t pkeepalive)"; pdf="${stub}.pdf"; mv "$stub" "$pdf"
    [ -z "$PYTHON" ] && { rm -f "$pdf"; echo "ERROR: python3 not found" >&2; return 1; }
    "$PYTHON" - "$pdf" "$tier" "$subtitle" <<'PY'
import sys
out, tier, subtitle = sys.argv[1], sys.argv[2], (sys.argv[3] if len(sys.argv) > 3 else "")
W, H = 595, 842                      # A4 points
inks = [(1,0,0,0,"C"),(0,1,0,0,"M"),(0,0,1,0,"Y"),(0,0,0,1,"K")]

MARGIN, TOP, BOTTOM = 40, 792, 40
usable = W - 2 * MARGIN
slot = usable / len(inks)
height = TOP - BOTTOM

# per-tier geometry: line width + horizontal offsets within each colour slot
if tier == "heavy":
    width, offsets = 28, [0]         # solid band per channel (deep flush)
elif tier == "medium":
    width, offsets = 3, [-11, 0, 11] # comb of 3 thin lines per channel
else:
    tier, width, offsets = "light", 3, [0]   # single thin line per channel

title = f"Inkjet nozzle keep-alive  -  {tier} flush"
lines = [
    f"BT /F1 12 Tf 0 0 0 1 k {MARGIN} 815 Td ({title}) Tj ET",
]
if subtitle:
    safe = subtitle.replace("(", " ").replace(")", " ").replace("\\", " ")
    lines.append(f"BT /F1 8 Tf 0 0 0 1 k {MARGIN} 800 Td ({safe}) Tj ET")

for i, (c, m, ye, kk, name) in enumerate(inks):
    xc = MARGIN + slot * (i + 0.5)
    for off in offsets:
        x = xc + off - width / 2.0
        lines.append(f"{c} {m} {ye} {kk} k {x:.1f} {BOTTOM} {width} {height} re f")
    lines.append(f"BT /F1 8 Tf 0 0 0 1 k {xc-2:.1f} {TOP+5} Td ({name}) Tj ET")

content = ("\n".join(lines) + "\n").encode("latin-1")

objs = [
    b"<< /Type /Catalog /Pages 2 0 R >>",
    b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    (f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {W} {H}] "
     f"/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>").encode("latin-1"),
    b"<< /Length %d >>\nstream\n" % len(content) + content + b"endstream",
    b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
]
buf = b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n"
offs = []
for i, body in enumerate(objs, 1):
    offs.append(len(buf)); buf += b"%d 0 obj\n" % i + body + b"\nendobj\n"
xref = len(buf)
buf += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1)
for o in offs: buf += b"%010d 00000 n \n" % o
buf += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, xref)
open(out, "wb").write(buf)
PY
    echo "$pdf"
}

# --- main ------------------------------------------------------------------
mkdir -p "$SCRIPTS" "$(dirname "$LOG")"
FORCE_TIER=""; DRY=0
case "${1:-}" in
    --dry)  DRY=1; FORCE_TIER="${2:-}";;
    --tier) FORCE_TIER="${2:-}";;
    "")     ;;
    *)      echo "usage: $(basename "$0") [--tier light|medium|heavy] [--dry [tier]]" >&2; exit 2;;
esac

TIER="${FORCE_TIER:-$(decide_tier)}"
case "$TIER" in light|medium|heavy) ;; *) TIER=$(decide_tier);; esac

DAYS=$(days_since)
TS="$(date '+%Y-%m-%d %H:%M:%S')"

# read the selected printers into an array (bash 3.2: no mapfile)
PRINTERS=()
while IFS= read -r _p; do [ -n "$_p" ] && PRINTERS+=("$_p"); done < <(get_printers)
PCOUNT=${#PRINTERS[@]}

# human-friendly "since last run" phrase + heads-up body
if [ "$DAYS" -lt 0 ]; then since="first run"; else since="last run ${DAYS}d ago"; fi
on=""; [ "$PCOUNT" -gt 1 ] && on=" on $PCOUNT printers"
case "$TIER" in
    light)  body="Nozzle keep-alive printing now${on} - routine ($since).";;
    medium) body="Catching up${on} - ${since}; printing a medium nozzle flush.";;
    heavy)  body="It's been a while${on} - ${since}; printing an intensive nozzle flush (2 pages each).";;
esac

# --- dry run: build + open, no printing, no state change -------------------
if [ "$DRY" = 1 ]; then
    PDF=$(build_pdf "$TIER" "$TS  -  $since  -  dry run")
    echo "[$TS] dry run ($TIER) - $PDF" | tee -a "$LOG"
    open "$PDF" 2>/dev/null || true
    exit 0
fi

if [ "$PCOUNT" -eq 0 ]; then
    echo "[$TS] ERROR: no printer selected and no system default" | tee -a "$LOG" >&2
    notify "Printer keep-alive failed" "No printer configured."
    exit 1
fi

# --- heads-up FIRST, then a short lead so it's actually a heads-up ----------
notify "Printer keep-alive" "$body"
LEAD=$(get_lead); [ "$LEAD" -gt 0 ] && sleep "$LEAD"

COPIES=1; [ "$TIER" = heavy ] && COPIES=2
NOW=$(date +%s); OK=0; FAILED=""

# print to every selected printer; one history row per printer
for P in "${PRINTERS[@]}"; do
    PDF=$(build_pdf "$TIER" "$TS  -  $since  -  printer: $P")
    if lp -d "$P" -n "$COPIES" -o media=A4 "$PDF" >/dev/null 2>>"$LOG"; then
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$NOW" "$TS" "$TIER" "$DAYS" "$COPIES" "$P" >> "$HISTORY_FILE"
        OK=$((OK+1))
    else
        echo "[$TS] FAILED to print to $P (see log)" | tee -a "$LOG" >&2
        FAILED="$FAILED $P"
    fi
    rm -f "$PDF"
done

[ "$OK" -gt 0 ] && echo "$NOW" > "$LASTPRINT_FILE"
if [ "$DAYS" -lt 0 ]; then gapmsg="first run"; else gapmsg="gap was ${DAYS}d"; fi
echo "[$TS] printed $TIER keep-alive to $OK/$PCOUNT printer(s); $gapmsg" | tee -a "$LOG"

if [ -n "$FAILED" ]; then
    notify "Printer keep-alive failed" "Could not print to:$FAILED"
    [ "$OK" -eq 0 ] && exit 1
fi
