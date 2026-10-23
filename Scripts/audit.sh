#!/bin/sh
# Re-checks the claims in SECURITY.md that can be checked mechanically.
# Run before every build you are going to use; exits non-zero on the first
# broken claim. With a built dist/SHTerminator.app it also checks the
# signature.
set -eu

cd "$(dirname "$0")/.."

fail() {
    echo "FAIL: $1" >&2
    exit 1
}
ok() {
    echo "ok:   $1"
}

# SECURITY.md §4 — no networking APIs in the app's own code.
if grep -rnE "URLSession|import Network|CFNetwork|NSURLConnection|NSURLDownload|CFStream|CFSocket|socket\(|connect\(|getaddrinfo|gethostbyname|WKWebView|WebKit|Data\(contentsOf: *URL\(string" Sources/SHTerminator; then
    fail "networking API used in Sources/SHTerminator"
fi
ok "no networking APIs in app code"

# SECURITY.md §5 — the one dependency is pinned to an exact version.
grep -q 'migueldeicaza/SwiftTerm", exact: "' Package.swift || fail "SwiftTerm is not pinned with exact: in Package.swift"
deps=$(grep -c '\.package(' Package.swift)
[ "$deps" -eq 1 ] || fail "expected exactly 1 package dependency, found $deps"
ok "single dependency, pinned exactly"

# SECURITY.md §6 — entitlements stay empty (no library-validation or JIT holes, no sandbox flip-flops).
if grep -q "<key>" SHTerminator.entitlements; then
    fail "SHTerminator.entitlements is not empty"
fi
ok "entitlements empty"

# SECURITY.md §1–3 — the hardening calls are still in place.
grep -q "sharingType = .none" Sources/SHTerminator/Security/SecurityHardening.swift || fail "sharingType = .none missing"
grep -q "isRestorable = false" Sources/SHTerminator/Security/SecurityHardening.swift || fail "isRestorable = false missing"
grep -q "RLIMIT_CORE" Sources/SHTerminator/Security/SecurityHardening.swift || fail "core dump limit missing"
grep -q "EnableSecureEventInput" Sources/SHTerminator/Security/SecurityHardening.swift || fail "secure keyboard entry missing"
ok "hardening calls present"

# Files written to disk only through the 0600 helper.
if grep -rnE "\.write\(to:|\.write\(toFile:|\.write\(toURL:|createFile\(atPath|FileHandle\((forWriting|forUpdating)|fopen\(|freopen\(|O_CREAT|O_WRONLY|O_RDWR|copyItem\(|NSKeyedArchiver|setHostLogging" Sources/SHTerminator | grep -v "SecurityHardening.swift"; then
    fail "file written outside SecurityHardening.writePrivateFile"
fi
ok "all file writes go through writePrivateFile"

# SECURITY.md §17 — what a program in a pane may ask of the terminal.
grep -q "terminalDelegate = hostRequestFilter" Sources/SHTerminator/PTY/TerminalPaneView.swift || fail "HostRequestFilter not installed on TerminalPaneView"
grep -A1 "func clipboardRead" Sources/SHTerminator/Security/HostRequestFilter.swift | grep -qx "        nil" || fail "OSC 52 clipboard read is not refused"
grep -qE "func clipboardCopy\(.*\) \{\}" Sources/SHTerminator/Security/HostRequestFilter.swift || fail "OSC 52 clipboard write is not refused"
if grep -rn "NSWorkspace.shared.open" Sources/SHTerminator | grep -v "HostRequestFilter.swift"; then
    fail "URL opened outside LinkPolicy"
fi
ok "OSC 52 refused, links limited by LinkPolicy"

# SECURITY.md §17 — the program's output reaches SwiftTerm only through HostOutputFilter.
grep -q "super.dataReceived(slice: hostOutputFilter.filter(slice)" Sources/SHTerminator/PTY/TerminalPaneView.swift || fail "HostOutputFilter not applied to the program's output"
if grep -rnE "\.feed\(|feed\((text|byteArray|buffer):" Sources/SHTerminator | grep -v "TerminalPaneView.swift"; then
    fail "terminal fed outside TerminalPaneView.feedLocally (bypasses HostOutputFilter)"
fi
swiftterm=$(sed -n 's/.*migueldeicaza\/SwiftTerm", exact: "\([0-9.]*\)".*/\1/p' Package.swift)
grep -q "SwiftTerm ${swiftterm})" Sources/SHTerminator/Security/HostOutputFilter.swift || fail "SwiftTerm is ${swiftterm} but HostOutputFilter mirrors another version's parser — re-check it"
ok "program output filtered against SwiftTerm ${swiftterm}'s parser"

# SECURITY.md §9 — a pane's pty is never inherited by later panes' shells.
grep -q "fcntl(fd, F_SETFD, FD_CLOEXEC)" Sources/SHTerminator/PTY/TerminalPaneView.swift || fail "pty not marked close-on-exec"
if grep -rn "startProcess(" Sources/SHTerminator | grep -v "TerminalPaneView.swift"; then
    fail "process started outside TerminalPaneView.startIsolatedProcess"
fi
ok "panes' ptys close-on-exec"

# SECURITY.md §1 — commands are not shown in tooltips (captured by screenshots).
if grep -rn "toolTip = favorite" Sources/SHTerminator; then
    fail "favorite shown in a tooltip"
fi
ok "no favorites in tooltips"

if [ -d dist/SHTerminator.app ]; then
    codesign --verify --strict dist/SHTerminator.app || fail "signature does not verify"
    codesign -d --verbose=2 dist/SHTerminator.app 2>&1 | grep -q "flags=.*runtime" || fail "Hardened Runtime not enabled on dist/SHTerminator.app"
    ok "dist/SHTerminator.app signed with Hardened Runtime"
fi

echo "All checks passed."
