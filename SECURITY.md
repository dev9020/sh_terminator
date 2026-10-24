# sh_terminator security model

This terminal is meant for ordinary everyday work, including the times
when passwords, private keys or seed phrases end up on screen in its
panes. Every decision below puts that first, sometimes at the cost of
convenience.

## What is protected and how to check it

### 1. No screenshots, screen sharing or screen recording of these windows

Every window is created with `NSWindow.sharingType = .none`
(`Sources/SHTerminator/Security/SecurityHardening.swift`), and it is set
again on `windowDidBecomeKey` and on entering or leaving full screen. This
is the standard AppKit API password managers use for their windows: the
window is left out of `CGWindowListCreateImage`, ScreenCaptureKit, the
built-in screenshot tools (⌘⇧4/⌘⇧5) and screen capture in
Zoom/Meet/Slack/QuickTime.

Check:
```
screencapture -l<windowID> /tmp/out.png   # -> "could not create image from window"
```
(the window number is `kCGWindowNumber` from `CGWindowListCopyWindowInfo`
for the sh_terminator process; the same window has `kCGWindowSharingState`
equal to `0`).

This check covers the older capture path (CGWindowList). Apps that capture
the screen through ScreenCaptureKit (on recent macOS: Zoom, Meet,
QuickTime, ⌘⇧5) use a different path, and there are reports that on
macOS 15+ it ignores `sharingType = .none`. Check by hand on every new
macOS version: start a screen recording with ⌘⇧5 or a screen share in
Zoom/Meet and make sure the sh_terminator window shows up as empty space.
If the window is visible, this item does not protect you on that macOS
version — keep secrets covered with the lock (⌃⌘L).

Only the app's own windows are protected (the launcher, terminal windows,
favorites, alert sheets). Tooltips and menus are separate system windows
that capture does include, so favorite commands are never shown in
tooltips (neither in the sidebar nor in the Favorites menu); the menu shows
only the favorites' *names*. The window title is visible outside the
window as well — see §17.

### 2. Pane contents are never written to disk

- `NSWindow.isRestorable = false` on every window: macOS never serializes
  their contents into `~/Library/Saved Application State/`.
- Each pane's scrollback lives only in the process's memory; the app keeps
  no session log on disk. The only things it writes to disk on its own are
  the favorite commands, the notes (see §11 and §12), the proxies for
  panes with their passwords (§18) and the settings —
  switches and numbers in
  `~/Library/Preferences/dev.local.shterminator.plist`, with no pane
  contents, commands or notes.
- The data files (favorites, notes, proxies) are written through
  `SecurityHardening.writePrivateFile`: a temporary file is created with
  mode `0600` from the start (`open(O_CREAT|O_EXCL, 0600)`), then `fsync`
  and an atomic `rename`. At no point does the file exist with
  umask-derived permissions. The directory is set to `0700` (`chmod`) on
  every write, even if it already existed with other permissions.
  `Scripts/audit.sh` checks that the code has no other way of writing
  files (`.write(to:/toFile:)`, `FileHandle`, `fopen`, `O_CREAT`,
  `copyItem`…).
- **Clear Scrollback** (⌘K) erases the focused pane's scrollback and every
  screen line above the cursor (the prompt line stays). This is hygiene
  against prying eyes and accidental copying, not a guarantee: SwiftTerm
  releases the lines' memory for reuse but does not zero it.

### 3. No core dumps on a crash

`setrlimit(RLIMIT_CORE, 0)` is the first line of `main.swift`
(`SecurityHardening.hardenProcess()`), before the application and its first
window exist — so the process's memory (possibly holding secrets) can never
be dumped to disk in a crash.

### 4. No networking in the app itself

The app's code (`Sources/SHTerminator`) does not import `URLSession`,
`Network.framework` or `CFNetwork` — a plain grep checks it:
```
grep -rn "URLSession\|Network\.framework\|CFNetwork" Sources/SHTerminator   # empty
```
(this and the other checks in this document are run by `Scripts/audit.sh`;
`build-app.sh` runs it after every build).
The Connection block in the sidebar reads only local state: interface
addresses (`getifaddrs`) and the SystemConfiguration dynamic store
(primary interface, service names, system proxies). It never looks up the
public IP, because that would mean asking an outside server.
The proxy for panes (§18) does not change this: the app only starts the
panes' shell differently. The one piece of networking code in the bundle
is `Resources/shell/sht-socks5`, a Perl helper that ssh (run by the user
in a pane) starts as its `ProxyCommand`; the app never runs it.
No auto-update, no analytics, no crash reporter — no such dependency has
been added and none is planned.

### 5. The single external dependency is pinned and transparent

`Package.swift` names an exact SwiftTerm version (`exact: "1.20.0"`),
locked to a specific commit in `Package.resolved`. `swift package update`
will never silently pull in another version — updating it takes an
explicit change to `Package.swift`. The `SwiftTerm` target has no
dependencies on macOS in its own `Package.swift` (its graphics packages
are conditional and used only on Linux/Windows/WASM);
`swift-argument-parser`, visible in `Package.resolved`, is needed only by
SwiftTerm's internal `Termcast` executable, which we neither use nor link.

### 6. Hardened Runtime with no code-injection loopholes

`Scripts/build-app.sh` signs the `.app` with `--options runtime` and
`SHTerminator.entitlements`. The entitlements file is empty — in
particular, there is **no** `com.apple.security.cs.disable-library-validation`
and **no** `com.apple.security.cs.allow-unsigned-executable-memory`. This
means a third-party `dylib` cannot be injected into the process by the
usual means (`DYLD_INSERT_LIBRARIES` and the like are blocked by Hardened
Runtime + library validation).

The signature is ad-hoc by default (`codesign --sign -`). Hardened Runtime
(blocking `DYLD_INSERT_LIBRARIES` and the like) works with it too, but an
ad-hoc signature identifies no one: anyone who can write to the `.app` can
replace the binary and re-sign it just as "validly", and Gatekeeper cannot
tell that copy apart. That is acceptable for personal use on one machine;
otherwise build with a real signature:
```
SIGN_IDENTITY="Developer ID Application: …" ./Scripts/build-app.sh
```
(list your identities with `security find-identity -v -p codesigning`),
and add notarization to distribute it to other machines.

### 7. App Sandbox is deliberately off

Unlike typical App Store apps, there is **no** `com.apple.security.app-sandbox`.
The reason: this is a terminal — the `ssh`/`git`/`curl`/package managers run
inside it need normal access to the network and the user's file system,
just as in the standard Terminal.app. Sandboxing the tool but not its only
payload (the shell) would create an illusion of protection with no real
effect.

### 8. A clean environment for the child process

`PaneSession` finds the login shell's path with `getpwuid_r` (as
Terminal.app itself does), not from the `SHELL` variable, which could be
tampered with before launch. The child shell's environment is built by
SwiftTerm (`Terminal.getEnvironmentVariables`) rather than inherited
wholesale from the app: `TERM=xterm-256color`, `COLORTERM=truecolor`,
`LANG=en_US.UTF-8` (hard-coded, whatever the system locale), plus
`LOGNAME`, `USER`, `HOME`, `DISPLAY`, `LC_TYPE` if they are present in the
app's own environment. On top of that the app passes only `TMPDIR`
(`PaneSession.shellEnvironment`): the user's private temporary directory
(`/var/folders/…`, `0700`) is set by launchd, not by the login shell, and
without it the shell and everything run in it would write temporary files
(here-docs, editor buffers) to `/tmp`, which all accounts share. `PATH`
and everything else is not passed on (the login shell sets them itself
from its rc files). Nothing else app-specific is added, except that zsh
gets the startup files of the proxy for panes (§18).

### 9. Isolation between panes

Each pane is a separate `PaneSession`, i.e. a separate shell process on
its own pty. Panes share no state beyond what any two independent OS
processes do.

SwiftTerm opens the pty with `forkpty`, and the terminal's "master" end
(`/dev/ptmx`), which the app keeps, is by default inherited by every
process started later. Without protection, the shell of each later pane
and everything run in it would hold the terminals of all earlier panes:
they could read their output and type commands into them (for example
into a pane with `ssh` to a production server or with `sudo -s`). So
`FD_CLOEXEC` is set on that descriptor right after the shell starts
(`TerminalPaneView.startIsolatedProcess`). The `PaneIsolationTests` test
checks it (via `lsof`, the second process has no `/dev/ptmx`), and
`Scripts/audit.sh` checks that shells are started only this way.

### 10. Clipboard hygiene (optional)

The **Edit → Copy & Clear Clipboard After 20s** menu item (⌥⌘C) copies
the selection and clears the system clipboard by itself 20 seconds later —
handy for pasting a password or seed phrase without it lingering in the
clipboard. Plain ⌘C keeps working as always — this is an extra command,
not a restriction.

Besides the timer, such a copy (and the "copy all" button, ⌘C and ⌘X in
the notes) — written as one item, text and markers together:
- is marked with the `org.nspasteboard.ConcealedType` and
  `org.nspasteboard.TransientType` types (nspasteboard.org) — clipboard
  managers (Maccy, Paste, Raycast, Alfred, 1Password…) do not save such
  entries in their history;
- is put on the clipboard with `NSPasteboard.ContentsOptions.currentHostOnly`
  — it is not passed through Universal Clipboard to an iPhone/iPad/other Mac.

Copying from the notes (the "copy all" button, ⌘C, ⌘X) clears the
clipboard after 20 seconds as well. Locking (§14) and quitting the app clear such a copy at once,
without waiting for the timer (which would not outlive the app anyway).

The clear only happens if the clipboard has not changed since
(`changeCount`): if you copied something else in the meantime, in any
app, it stays.

A clipboard manager that ignores these markers will still record the
entry — that is outside the app's control.

Programs in panes have no access to the clipboard: they can neither read
nor write it through OSC 52 (§17).

### 11. Favorite commands

Favorite commands are stored on disk:
`~/Library/Application Support/SHTerminator/favorites.json`, directory
`0700`, file `0600` (readable by your user only). It is plain text, so
**do not put passwords directly into a command** — for databases use
`~/.my.cnf` / `~/.pgpass`, `mysql --login-path`, ssh keys and so on, and
type the password when prompted.

Inserting a favorite never runs the command: trailing line breaks are
dropped, and inner ones are kept only if the command goes into the pane's
own shell prompt — zsh or fish — with bracketed paste on (then the shell
will not run it by itself). In every other case inner line breaks are
replaced with spaces: bracketed paste mode is just a flag that any program
or any output can switch on, including a program that does not honour it
(see §15). Control characters (including `ESC`, which could end a
bracketed paste early) are always removed from the inserted command,
wherever it came from (a terminal selection via ⌘⇧S, a placeholder value,
a hand-edited `favorites.json`). The same applies to each pane separately
in broadcast mode (§16). The favorites manager window is also excluded
from screenshots and screen sharing.

### 12. Notes

The **Notes** box in the sidebar is saved to
`~/Library/Application Support/SHTerminator/notes.txt` (directory `0700`,
file `0600`) so the text survives a restart. It is plain text: if you
pasted a password or seed phrase into it, delete it as soon as you no
longer need it. When the box is cleared (the trash button or deleting all
the text), the file is deleted from disk rather than left empty. The
deleted file is not overwritten, though: its contents may survive on disk
and in Time Machine backups. So do not keep secrets in the notes for long.
If **Keep Notes Across Restarts** is turned off in the app menu, the notes
live in memory only: the file is deleted at once and never created again,
and the text is gone when the app quits.
Spell checking, autocorrect, smart quotes, link detection and Writing
Tools (Apple Intelligence, macOS 15+) are off in this box — pasted text is
not changed and is not sent to the system's text checking and rewriting
services. The same goes for every editable field in the app: the name and
command in the favorites window, placeholder values, the sidebar search
(`PlainTextField` / `PlainSearchField`) — otherwise system autocorrect
could quietly turn `"` into `“` or `--` into `—` in a command. Services are
disabled for this box, and its context menu keeps only Cut / Copy / Paste /
Select All (no Look Up, Translate, Share, Speech).

### 13. Secure Keyboard Entry

While the app is active (and **Secure Keyboard Entry** in the app menu is
on — it is by default), `EnableSecureEventInput()` is called; when it goes
to the background, `DisableSecureEventInput()`. While it is on, other
processes' `CGEventTap`s — the usual way keyloggers and "utilities" with
Input Monitoring permission read keystrokes — get nothing typed here,
including passwords at `sudo`, `ssh` and `gpg` prompts. This is the same
mechanism as "Secure Keyboard Entry" in Terminal.app and iTerm2.

Check (with the sh_terminator window active):
```
ioreg -l -w 0 | grep kCGSSessionSecureInputPID   # = PID of the SHTerminator process
```
The app's settings (this one included) live in
`~/Library/Preferences/dev.local.shterminator.plist`, which any process of
your user can change. So they are read once at launch (a running app can't
be switched off from outside), launch arguments such as
`-secureKeyboardEntry NO` are ignored, and a protection that is weaker
than its default — Secure Keyboard Entry off, Lock When Mac Sleeps off,
Show Pane Title in Window Title on — is shown in red at the bottom of every
window, even with the shortcuts bar turned off.

Side effect: while the window is active, global hotkeys and auto-typing of
some third-party apps (text expanders, password managers' auto-type) may
not work — this is intended.

### 14. Window lock

- **Lock Now** (⌃⌘L), **Auto-Lock** (after 1/5/15/30 minutes without
  input in this app; the check keeps running while a menu or an alert is
  open) or **Lock When Mac Sleeps or Screen Locks** (on by
  default: the Mac sleeping, the displays sleeping, the screen being
  locked, switching to another user): every window removes its panes and
  sidebar entirely and shows an opaque lock screen. The shells keep
  running. Only Touch ID or the macOS account password can unlock it
  (`LAContext`, `.deviceOwnerAuthentication`).
- **Hide Windows When in Background**: while another app is active, the
  windows are covered by the same screen (without authentication — it is
  lifted when you return to the app). Protects against someone looking at
  a window left visible behind others.
- While the windows are covered, nothing reaches a shell: the panes are not
  in the view hierarchy, so keystrokes, clicks, inserting favorites, ⌘V,
  broadcast and the other menu items that act on panes are unavailable.
  New windows and the favorites window cannot be opened either (the
  favorites window is hidden).
- The security settings in the app menu (Secure Keyboard Entry, Auto-Lock,
  Lock When Mac Sleeps, Hide Windows When in Background, Show Pane Title in
  Window Title, Keep Notes Across Restarts) are unavailable while locked:
  whoever sits at the locked window cannot weaken them or delete the notes
  from disk. Only Lock Now and Quit remain available.
- A sheet open on a window (paste check, placeholders, close confirmation,
  opening a link) is cancelled when the lock engages — it does not stay on
  top of the cover showing a command's text and does not take Return. The
  window title is reset to `sh_terminator` while locked.

### 15. Paste check (⌘V)

Text is checked before it is pasted (`Security/PastePolicy.swift`):
- **Control characters** (C0 other than tab and line breaks, DEL, C1) —
  always a question; the default is to paste without them. With
  `ESC[201~`, a fragment hidden in text copied from a web page can end a
  bracketed paste early, and the rest (with a line break) would run as if
  typed by hand.
- **Line breaks** — each of them may act as Return. A multi-line paste
  goes through without a question only into the pane's own shell prompt,
  zsh or fish, with bracketed paste on — they switch that mode on
  themselves at every prompt and do not run pasted lines. "At the prompt"
  means the shell's line editor has the terminal (non-canonical, no
  echo), not merely that the shell is in the foreground: while the shell
  itself runs `read`, `vared` or `select`, the first line would go to that
  builtin and the rest would be read by the line editor as typed keys. In every other
  case there is a question with the options "paste as one line" (default),
  "paste and run lines" (or "paste as is" if the program turned bracketed
  paste on) and "cancel". A mode turned on by any other program (`ssh`, a
  REPL, `sh`, macOS's bash 3.2) is not trusted: any output can turn it on —
  a `cat`-ed file, a remote server's banner — including just before a
  program that does not honour it and will run every line.
  If the program turns bracketed paste off while the question is up,
  "paste as is" asks again instead of pasting the lines as they are.

The warning text never shows the clipboard contents (they may be a secret,
and the alert is a separate window).

### 16. Broadcast

⌥⌘I sends input to every pane of the window. The terminal's own replies to
the program (cursor position, device attributes and so on) are not
broadcast — only what the user typed or pasted. While broadcast is on,
every pane's header is red.

- **A paste** (⌘V, favorites) is handled in each pane according to *its*
  program: unless it is a zsh/fish prompt with bracketed paste (§15), line
  breaks are replaced with spaces and nothing runs — even if the source
  pane asked no question. The exception is an explicit "Paste and Run
  Lines": then the lines run in every pane, and the dialog warns about it.
  "Paste As Is" keeps line breaks only in the source pane (its program
  promised not to run them); in the other panes the paste is handled
  according to their program, as usual.
- **Typing and pasting at a password prompt.** If the source pane is at a
  local password prompt (`sudo`/`ssh`/`gpg`: the terminal is canonical
  with echo off), keystrokes and pasted text go only to panes at such a
  prompt too. So a `sudo` password typed once for all panes still works,
  but is never printed in plain text at a neighbouring pane's shell prompt
  (or stored in its history). Echo being off alone is not the test: the
  shells' own line editors (zsh, bash, fish) turn the terminal's echo off
  at every prompt and echo keys themselves.
  Limitation: a pane running `ssh` keeps its local terminal raw (the
  remote side does the echoing), so a password prompt on the remote host
  looks like ordinary input there and is broadcast like it.

### 17. What a program in a pane may ask of the terminal

Any program in a pane can ask the terminal for something with an escape
sequence — including a remote server behind `ssh`, or a file you merely
printed with `cat`. Therefore (`Security/HostRequestFilter.swift`):
- **Clipboard (OSC 52)**: reading is refused (otherwise the program would
  get whatever is on the clipboard, such as a password you just copied),
  and so is writing (otherwise it could silently replace the clipboard
  with a command you would later paste somewhere else). Only you copy
  (⌘C, ⌥⌘C).
- **Links** (⌘-click, including OSC 8, where the program sets both the
  link text and its address): only `http`, `https` and `mailto` are
  opened. Files, applications and arbitrary URL schemes are not
  (`file:///…/x.command` would run a script) — a beep sounds instead. An
  allowed link opens only after confirmation in a sheet that shows its
  real address (percent-encoded, at most 1000 characters) — the link text
  on screen may say something else.
- **Screen contents (DECRQCRA, `CSI … y`)**: SwiftTerm answers this
  request with a checksum of a screen rectangle, and for a single cell
  that checksum equals the character's code — so a program (including a
  remote server behind `ssh`) could read everything visible in the pane
  character by character, including what was printed before it ran. This
  cannot be turned off in SwiftTerm, so all of the program's output passes
  through `Security/HostOutputFilter.swift`: such a request is cut off
  (its last byte replaced with SUB) and left unanswered.
- **Local files via Kitty graphics** (APC `G` with `t=f`, `t=t`, `t=s`):
  such a request would make the terminal itself open a local file or
  shared memory named by the program — a remote server would learn from
  the reply whether you have such a file, could make the app read up to
  400 MB, or show a permission prompt for ~/Documents in the app's name.
  The same filter cuts such commands off (CAN before the end of the
  sequence), and the terminal does not carry them out. Images sent inline
  in the output (`t=d`, the default) work.
  The filter is a shadow copy of SwiftTerm 1.20.0's parser state machine
  (the same transition table and the same shortcuts), so it sees a
  sequence exactly where SwiftTerm will see it, however the output is
  split into chunks; all other output passes unchanged.
  `HostOutputFilterTests` check this against SwiftTerm's real parser,
  fuzzing included. When SwiftTerm is updated, the filter must be
  re-checked — `Scripts/audit.sh` fails if the versions in `Package.swift`
  and in the filter differ.
- **Title (OSC 0/2)**: control characters, line breaks, bidi override
  characters (which can reorder visible text) and invisible characters
  (zero-width space/joiner, tag characters and the like, which can make two
  titles look identical) are removed from it, and its length is capped at
  200 characters. The title is shown in the bar above the pane — inside
  the protected window. It reaches the *window* title only if **Show Pane
  Title in Window Title** is on (off by default): the window title is
  visible outside the window — in the Dock icon's menu, Mission Control, to
  Accessibility clients and in the window list (`kCGWindowName`) of apps
  with Screen Recording permission, and many zsh/bash setups write the
  whole current command into the title, password included if it was on
  the command line.

`Scripts/audit.sh` checks that the filter is installed, OSC 52 is refused,
and URLs are opened only through `LinkPolicy`.

### 18. Proxy for panes

**sh_terminator → Proxy for Panes…** keeps a list of SOCKS5 proxies, at
most one of them in use, and which programs go through it: curl, git and
brew by default, ssh (with scp and sftp) only when turned on.

How it reaches them (`ProxyStore.paneEnvironment`). Every pane whose
login shell is zsh gets `ZDOTDIR` pointing at `Contents/Resources/shell`
inside the signed app, the path of the app's binary and the path of
`proxies.json` — no proxy address or password. Those zsh startup files
first run the user's own (`~/.zshenv`, `~/.zprofile`, `~/.zshrc`,
`~/.zlogin`, at top level with `ZDOTDIR` set back), then define shell
functions for curl, git, brew, ssh, scp and sftp, then hand `ZDOTDIR`
back. Before each run a function `stat`s `proxies.json`; only when it
changed does it run `SHTerminator --pane-proxy` to learn which programs
go through which proxy. So adding, changing or turning off a proxy
applies to open panes from their next command on. If the app can't be
asked, the function refuses to run the program rather than run it
without the proxy. Other login shells get nothing and start as in §8.

- **The password.** It is saved with the proxy in `proxies.json` —
  plain JSON, readable only by you (`0600`, written like the favorites,
  §2), never in the settings plist. Not in the Keychain, on purpose: the
  app's ad-hoc signature (§6) changes with every build, and macOS would
  ask for Keychain access again each time. So anyone who can read your
  files (a process running as you, a backup of your home folder) can read
  the password; use a proxy password you don't use anywhere else. The
  panes get it from the app's own binary in `--pane-proxy` mode, which
  answers only a process that has the running app (the same executable)
  among its ancestors, i.e. something started from one of its panes. In
  the pane it lives in a plain shell parameter, not the environment, so
  it is not inherited by everything the shell runs; only the wrapped
  program gets it, in its own environment (`all_proxy` and friends for
  curl/git/brew, `SHT_PROXY_URL` for the ssh helper). It is never put on a
  command line, which other users could read with `ps`. This is a
  convenience proxy password, not a vault.
- **ssh through a proxy.** The SSH session is encrypted end to end and
  the server's host key is checked as usual; the proxy sees only which
  server you connect to, when, and how much traffic. The one dangerous
  moment is the first connection to a server not yet in `known_hosts`:
  a hostile proxy could put itself in the middle, and answering `yes`
  without comparing the fingerprint lets it. This is why ssh is off by
  default. The helper (`sht-socks5`) speaks SOCKS5 with user/password
  (RFC 1928/1929) and sends the server's name to the proxy as is, so it is
  looked up by the proxy, not this Mac's DNS. It uses only Perl core
  modules and `/usr/bin/perl`.
- **curl, git, brew.** HTTPS stays encrypted (the proxy sees host names);
  plain HTTP passes through the proxy readable and changeable. With
  **Look up server names through the proxy** (`socks5h`, on by default)
  names are resolved by the proxy; with plain `socks5` this Mac's DNS
  resolves them first, which tells your provider where you go.
- **Limits.** zsh only (other login shells get no proxy, and the window
  says so). Only commands typed in the pane's zsh are wrapped: scripts,
  other shells, tmux and programs that call ssh/curl themselves bypass it
  (git's own ssh is covered through `GIT_SSH_COMMAND`). The `-o
  ProxyCommand` given to ssh wins over `ProxyJump`/`ProxyCommand` in
  `~/.ssh/config`.

`Scripts/audit.sh` checks that `Resources/shell` holds only these files,
that `.zshenv` takes the app's variables out of the environment, and that
the helper reads the URL from the environment, not its arguments.

## What this does not cover (accepted residual risks)

- **The Accessibility API (AXUIElement).** In theory another app that the
  user has granted Accessibility permission in System Settings can read
  on-screen text even with screenshot protection on — that is a separate
  channel, unrelated to `sharingType`. The surface is reduced because
  SwiftTerm draws the terminal with CoreText/Metal rather than a standard
  accessible `NSTextView`, but a single app cannot rule it out entirely.
  Recommendation: periodically review which apps have access under System
  Settings → Privacy & Security → Accessibility.
- **Commands the user runs in the shell** have the same rights as in
  plain Terminal.app — the app does not restrict processes the user starts
  (see §7 on App Sandbox).
- **Keyloggers at the OS, firmware or hardware level** — beyond the
  control of any single app.
- **Menus and tooltips** are separate system windows, visible in
  screenshots and screen sharing (§1): favorites' names in the Favorites
  menu, and the window title if **Show Pane Title in Window Title** is on
  (§17).
- **Find (⌘F)** uses the system find pasteboard, like any macOS app: the
  search string becomes visible in other apps' find fields. Do not search
  for secrets.
- **Moving clipboard contents into a document or file by hand** — if the
  user pastes a secret into another app, what happens to it from then on
  is outside sh_terminator's responsibility.

## What will NOT be added without a separate explicit request

Auto-update, telemetry/analytics of any kind, a crash reporter, cloud sync
of settings/sessions, session log export by default (enabling it must be
an explicit opt-in, and only to a path the user chooses).
