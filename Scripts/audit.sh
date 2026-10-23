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
if grep -rnE "URLSession|import Network|CFNetwork|NSURLConnection|CFStream|socket\(" Sources/SHTerminator; then
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
if grep -rnE "\.write\(to:|createFile\(atPath" Sources/SHTerminator | grep -v "SecurityHardening.swift"; then
    fail "file written outside SecurityHardening.writePrivateFile"
fi
ok "all file writes go through writePrivateFile"

if [ -d dist/SHTerminator.app ]; then
    codesign --verify --strict dist/SHTerminator.app || fail "signature does not verify"
    codesign -d --verbose=2 dist/SHTerminator.app 2>&1 | grep -q "flags=.*runtime" || fail "Hardened Runtime not enabled on dist/SHTerminator.app"
    ok "dist/SHTerminator.app signed with Hardened Runtime"
fi

echo "All checks passed."
