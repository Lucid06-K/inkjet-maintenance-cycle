# Printer Keep-Alive

Keeps an idle **inkjet** printer's nozzles from drying out / clogging by
printing a tiny page on a schedule. Each page fires every ink channel
(C / M / Y / K) as a **full-height line**, because inkjet nozzles sit in
vertical columns and the carriage sweeps sideways — so a full-height line
drives every nozzle of its colour while using a sliver of ink.

Periodic light printing is much cheaper than letting nozzles clog and then
running the printer's own cleaning cycle (which purges a lot of ink).

## Install

```sh
./install.sh
```

This installs into `~/Library/Scripts`, builds a notifier app, registers a
launchd agent (every 14 days), and adds a `pkeep` alias. Then:

```sh
pkeep printer "Your_Printer_Name"   # see names with: lpstat -p
pkeep run                           # print one now to test
```

## The `pkeep` command

Run `pkeep` with no arguments for an interactive UI (↑/↓ move, enter select,
q quit). Or use subcommands:

| Command | Does |
|---|---|
| `pkeep status` | show agent / printer / schedule / last-print |
| `pkeep run [tier]` | print now (`light`/`medium`/`heavy`; default auto) |
| `pkeep preview [tier]` | build + open the page **without** printing |
| `pkeep on` / `off` | enable / disable the scheduled keep-alive |
| `pkeep log [n]` | recent print history |
| `pkeep notify on\|off` | heads-up notification before each print |
| `pkeep printer` | list selected printers |
| `pkeep printer NAME` | set the list to just NAME |
| `pkeep printer add\|rm NAME` | add / remove a printer from the cycle |
| `pkeep interval [days]` | show / set the schedule interval |
| `pkeep lead [secs]` | show / set the heads-up lead time |
| `pkeep update` | fetch + verify + install the latest version |
| `pkeep autoupdate on\|off` | opt-in daily auto-update |

## Multiple printers

Have more than one printer? **Settings ▸ Printers** shows every printer macOS
knows about with a checkbox — tick as many as you like and the keep-alive runs
on **all** of them each cycle. (Or from the CLI: `pkeep printer add NAME`.)

## Updating

`pkeep update` installs the latest version, and **Settings ▸ Auto-update** turns
on a daily check. Updates are fetched over HTTPS-pinned `curl` and installed only
if the `SHA256SUMS` manifest carries a valid RSA-3072 signature from the
project's offline key **and** each file's checksum matches **and** it passes a
`bash -n` syntax check. The previous version is saved as `*.bak`. See
[SIGNING.md](SIGNING.md) for the maintainer signing process.

## Auto intensity (catch-up)

Intensity is chosen from how long it's been since the last **successful**
print, so if the Mac was off/asleep across scheduled runs it catches up:

| Gap since last print | Tier | Page |
|---|---|---|
| ≤ 1.5× interval | **light** | 1 thin line per channel (routine) |
| ≤ 3× interval | **medium** | 3-line comb per channel |
| > 3× interval | **heavy** | solid band per channel, printed ×2 (deep flush) |

## Heads-up notification

Before each print a notification fires (default 8s lead) so nobody's
surprised by the printer waking. Posted via a small `.app` applet because
bare `osascript` under launchd has no bundle ID and gets dropped silently.

## Requirements & notes

- macOS. The Mac must be **on and logged in**; if it's asleep at the
  scheduled time the print runs on the next wake. The **printer must be
  powered on** to actually print (otherwise the job waits in the queue).
- The page is A4; it prints fine on Letter too.
- State and logs live in `~/Library/Scripts/printer_keepalive.*` and
  `~/Library/Logs/printer-keepalive.log`.

## Uninstall

```sh
./uninstall.sh            # remove agent, scripts, applet, alias
./uninstall.sh --purge    # also remove state + logs
```
