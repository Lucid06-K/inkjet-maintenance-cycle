#!/bin/bash
# Copyright 2026
# SPDX-License-Identifier: Apache-2.0
#
# Installer for Printer Keep-Alive.
#   - ~/Library/Scripts/printer-keepalive.sh   the worker (prints + notifies + logs)
#   - ~/Library/Scripts/pkeep                  the control UI / CLI
#   - ~/Library/Scripts/PrinterKeepaliveNotifier.app   posts notifications
#   - ~/Library/LaunchAgents/com.printer-keepalive.agent.plist   the schedule
#   - 'pkeep' shell alias
set -euo pipefail

SRC="$(cd "$(dirname "$0")/src" && pwd)"
SCRIPTS="$HOME/Library/Scripts"
AGENTS="$HOME/Library/LaunchAgents"
LABEL="com.printer-keepalive.agent"
PLIST="$AGENTS/$LABEL.plist"
WORKER="$SCRIPTS/printer-keepalive.sh"
CTL="$SCRIPTS/pkeep"
NOTIFY_APP="$SCRIPTS/PrinterKeepaliveNotifier.app"
UID_NUM="$(id -u)"
INTERVAL_DEFAULT=1209600   # 14 days

bold() { printf '\n\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
info() { printf '  \033[2m•\033[0m %s\n' "$1"; }

bold "Printer Keep-Alive — installing for $(whoami)"

# 1) scripts ----------------------------------------------------------------
mkdir -p "$SCRIPTS" "$AGENTS" "$HOME/Library/Logs"
install -m 0755 "$SRC/printer-keepalive.sh" "$WORKER"
install -m 0755 "$SRC/pkeep" "$CTL"
ok "Installed scripts into ~/Library/Scripts"

# 2) notifier applet --------------------------------------------------------
# Bare osascript under launchd has no bundle ID, so Notification Center drops it
# silently. An osacompile .app has an identity macOS can grant + remember. The
# applet receives its payload via env vars (PKA_TITLE / PKA_BODY) because an
# osacompile applet's binary does NOT get command-line argv under launchd.
NOTIFY_AS='on run argv
    set theTitle to "Printer Keep-Alive"
    set theBody to ""
    try
        set theBody to (system attribute "PKA_BODY")
    end try
    try
        set tt to (system attribute "PKA_TITLE")
        if tt is not "" then set theTitle to tt
    end try
    if theBody is "" then
        try
            set theBody to (item 1 of argv)
        end try
    end if
    if theBody is "" then set theBody to "Nozzle keep-alive"
    display notification theBody with title theTitle
end run'
if [ ! -d "$NOTIFY_APP" ]; then
    osacompile -o "$NOTIFY_APP" -e "$NOTIFY_AS"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.printer-keepalive.notifier" \
        "$NOTIFY_APP/Contents/Info.plist" 2>/dev/null || true
    codesign --force --sign - "$NOTIFY_APP" 2>/dev/null || true
    ok "Built PrinterKeepaliveNotifier.app (notifications)"
else
    info "PrinterKeepaliveNotifier.app already present — keeping it (preserves permission)"
fi

# 3) launch agent -----------------------------------------------------------
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$WORKER</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin</string>
    </dict>
    <key>StartInterval</key>
    <integer>$INTERVAL_DEFAULT</integer>
    <key>RunAtLoad</key>
    <false/>
    <key>ProcessType</key>
    <string>Background</string>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/printer-keepalive.out.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/printer-keepalive.err.log</string>
</dict>
</plist>
PLIST
ok "Installed launch agent ($LABEL)"

# 4) load it ----------------------------------------------------------------
launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID_NUM" "$PLIST" 2>/dev/null || true
launchctl enable "gui/$UID_NUM/$LABEL" 2>/dev/null || true
ok "Loaded and enabled the keep-alive (every $(( INTERVAL_DEFAULT / 86400 )) days)"

# 5) alias ------------------------------------------------------------------
RC="$HOME/.zshrc"; case "${SHELL:-}" in */bash) RC="$HOME/.bashrc";; esac
touch "$RC" 2>/dev/null || true
RC_DISP="${RC/#$HOME/~}"
if grep -q 'alias pkeep=' "$RC" 2>/dev/null; then
    info "'pkeep' alias already present in $RC_DISP"
else
    printf '\n# Printer Keep-Alive — nozzle anti-clog control\nalias pkeep="%s"\n' "$CTL" >> "$RC"
    ok "Added 'pkeep' alias to $RC_DISP"
fi

# 6) notification permission prompt ----------------------------------------
echo
bold "One-time permission — macOS may ask to allow Notifications. Click Allow."
PKA_BODY="Printer Keep-Alive is installed 🎉" PKA_TITLE="Printer Keep-Alive" \
    "$NOTIFY_APP/Contents/MacOS/applet" >/dev/null 2>&1 || true

echo
ok "Done. Run 'pkeep' (open a new shell first, or: source $RC_DISP)"
info "Set your printer:  pkeep printer \"Your_Printer_Name\""
info "Print one now:     pkeep run"
