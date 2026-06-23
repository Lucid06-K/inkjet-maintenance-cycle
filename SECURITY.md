# Security Policy

Thanks for helping keep **Printer Don't Die Please!!** and its users safe.

## Supported versions

This is a single-track, rolling release: only the **latest version** is supported.
If you're not current, update before reporting:

```sh
pkeep update     # installs the latest verified version
pkeep version    # shows what you have
```

| Version | Supported |
|---|---|
| Latest (`main` / newest release) | ✅ |
| Anything older | ❌ — please `pkeep update` first |

## Reporting a vulnerability

**Please do _not_ open a public issue for security problems.**

Report privately through GitHub's **Private vulnerability reporting**:

> Repo **Security** tab → **Report a vulnerability** → fill in the advisory form.

(Direct link: `https://github.com/Lucid06-K/inkjet-maintenance-cycle/security/advisories/new`)

Please include:

- what you found and where (file + line, or the relevant `pkeep` command / menu path),
- steps to reproduce, or a minimal proof of concept,
- the impact you think it has, and
- your `pkeep version` and macOS version.

**What to expect:**

- **Acknowledgement:** within ~7 days.
- **Assessment & fix:** for a confirmed issue, a patch is shipped on `main`
  (delivered to users via `pkeep update`) as quickly as is practical, and the
  advisory is published once a fix is available.
- **Credit:** you'll be credited in the advisory unless you'd prefer to stay anonymous.

If you can't use GitHub private reporting, open a normal issue titled
**"security — please contact me"** with **no technical details**, and a
maintainer will arrange a private channel.

## Scope

Most relevant areas to look at:

- **The auto-updater** (`pkeep update` / opt-in auto-update) — the only part
  that fetches and runs remote code. It is HTTPS-pinned and installs only a
  release whose `SHA256SUMS` manifest carries a valid RSA-3072 signature from
  the project's offline key (see [SIGNING.md](SIGNING.md)), then verifies each
  file's checksum and runs a `bash -n` syntax check before replacing anything.
- **The launchd agent** (`com.printer-keepalive.agent`) and the notifier helper
  app (`PrinterKeepaliveNotifier.app`).
- **What gets printed.** The tool only ever submits a small generated PDF to a
  printer you selected via `lp`; it does not read your documents or print
  history beyond its own log.

## What this tool does NOT do

- It does not require `sudo` and runs entirely in user space.
- It does not transmit any data anywhere except fetching its own update files
  from this repo over HTTPS.
- It never deletes files; the worst it does is submit a small print job.
