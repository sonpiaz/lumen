# Releasing Lumen

Signing + notarization are designed as a **reusable credential block**: set it up
once, and every future `./scripts/release.sh` run — by you or any agent on this
machine — works non-interactively. Secrets live in the macOS **login keychain**,
never in this repo. Scripts reference them by name only.

The credentials are **team-level** (Affitor LLC, team `448LBGWBYM`), so the same
setup covers every Mac app under that team, not just Lumen.

## The two pieces (both in the keychain)

1. **Developer ID Application certificate** — signs the app for distribution
   outside the App Store. Already present:
   `Developer ID Application: Affitor LLC (448LBGWBYM)`.
   (Check: `security find-identity -v -p codesigning`.)

2. **A notarytool keychain profile** — credentials to submit to Apple's notary
   service. Created once with `xcrun notarytool store-credentials`.

## One-time setup

### a) Create an App Store Connect API key (recommended)

App-specific passwords work too, but API keys don't expire or rotate and are
scoped — the better fit for automation.

1. [App Store Connect](https://appstoreconnect.apple.com) → **Users and Access →
   Integrations → App Store Connect API** → **+** → role **Developer**.
2. Download `AuthKey_XXXX.p8` (one-time download). Note the **Key ID** and the
   **Issuer ID** (shown above the keys table).

### b) Store it in the keychain (once)

```bash
xcrun notarytool store-credentials "affitor-notary" \
  --key /path/to/AuthKey_XXXX.p8 --key-id <KEY_ID> --issuer <ISSUER_ID>
```

After this the `.p8` file can be deleted — the credential is in the keychain.

### c) Let codesign use the key without prompting (once)

So an agent never hits a "codesign wants to access the key" dialog:

```bash
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
  -k "<your login password>" ~/Library/Keychains/login.keychain-db
```

## Cutting a release (repeatable, non-interactive)

```bash
./scripts/release.sh 0.1.0
```

This builds, signs with the Developer ID identity, packages a drag-to-Applications
`.dmg`, notarizes it via the `affitor-notary` profile, and staples the ticket.
Then attach it to a GitHub release:

```bash
gh release create v0.1.0 dist/Lumen.dmg --title "Lumen v0.1.0" --generate-notes
```

## Overrides (env)

| Variable | Default |
|---|---|
| `LUMEN_SIGN_IDENTITY` | `Developer ID Application: Affitor LLC (448LBGWBYM)` |
| `LUMEN_NOTARY_PROFILE` | `affitor-notary` |
| `LUMEN_TEAM` | `448LBGWBYM` |
