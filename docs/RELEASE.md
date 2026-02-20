# Release Pipeline — Setup Guide

This document explains how to set up the automated release pipeline for ClawDeck.

## Architecture

```
Tag v1.2.0 on GitHub
  → GitHub Actions builds & archives with xcodebuild
  → Signs with Developer ID certificate
  → Notarizes with Apple (~2-5 min)
  → Creates DMG (drag-to-Applications)
  → Signs DMG with Sparkle EdDSA key
  → Uploads DMG to GitHub Release
  → Publishes appcast.xml to GitHub Pages

User's ClawDeck
  → Sparkle checks appcast.xml on launch (+ every 4h)
  → "New version available" dialog
  → One-click: download → verify → replace → relaunch
```

## Prerequisites

- **Apple Developer Program** ($99/year) — [Enroll here](https://developer.apple.com/programs/enroll/)
- **Developer ID Application** certificate (created after enrollment)
- **Xcode** on your Mac (for certificate management and key generation)

## One-Time Setup

### 1. Generate Sparkle EdDSA keys

Sparkle uses EdDSA (Ed25519) to verify that updates are authentic.

```bash
# Clone Sparkle tools (or find them in Xcode's SPM cache)
curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/2.7.5/Sparkle-2.7.5.tar.xz" \
  | tar xJ -C /tmp/sparkle-tools

# Generate keys — stores private key in macOS Keychain
/tmp/sparkle-tools/bin/generate_keys
```

This prints your **public key** (a base64 string). Copy it.

```bash
# Export the private key for CI
/tmp/sparkle-tools/bin/generate_keys -x /tmp/sparkle_private_key.txt
cat /tmp/sparkle_private_key.txt
# → Save contents as GitHub secret: SPARKLE_PRIVATE_KEY
rm /tmp/sparkle_private_key.txt
```

**Update `ClawDeck/Info.plist`:** Replace `REPLACE_WITH_YOUR_SPARKLE_PUBLIC_KEY` with the public key string.

### 2. Export Developer ID certificate as .p12

```bash
# In Keychain Access:
#   1. Open "My Certificates"
#   2. Find "Developer ID Application: ..."
#   3. Right-click → Export → save as DeveloperID.p12
#   4. Set a password (or leave empty)

# Base64-encode for GitHub secret
base64 -i DeveloperID.p12 | pbcopy
# → Paste as GitHub secret: DEV_ID_P12_BASE64
```

### 3. Create App-Specific Password

1. Go to [appleid.apple.com](https://appleid.apple.com)
2. Sign In → App-Specific Passwords → Generate
3. Label it "ClawDeck CI"
4. Save as GitHub secret: `APPLE_APP_PASSWORD`

### 4. Create the updates repo

1. Go to [GitHub → New Repository](https://github.com/new)
2. Name: `clawdeck-updates` (public)
3. Initialize with a README
4. Go to **Settings → Pages** → Deploy from branch: `main`, folder: `/ (root)`
5. Appcast URL will be: `https://1devstudio.github.io/clawdeck-updates/appcast.xml`

### 5. Generate deploy key

The release workflow needs write access to the updates repo.

```bash
ssh-keygen -t ed25519 -C "clawdeck-deploy" -N "" -f /tmp/clawdeck_deploy_key

# Public key → add to clawdeck-updates repo:
#   Settings → Deploy Keys → Add → paste public key → ✅ Allow write access
cat /tmp/clawdeck_deploy_key.pub

# Private key → add to clawdeck repo as secret:
cat /tmp/clawdeck_deploy_key
# → Save as GitHub secret: DEPLOY_KEY

rm /tmp/clawdeck_deploy_key /tmp/clawdeck_deploy_key.pub
```

### 6. Find your Team ID

```bash
# From Xcode:
# Xcode → Settings → Accounts → click your team → Team ID is shown

# Or from an existing certificate:
security find-identity -v -p codesigning | grep "Developer ID"
# The 10-character string in parentheses is your Team ID
```

## GitHub Secrets Checklist

Add these to the `1devstudio/clawdeck` repo under **Settings → Secrets and variables → Actions**:

| Secret | Description | Example |
|---|---|---|
| `DEV_ID_P12_BASE64` | Base64 of Developer ID .p12 certificate | `MIIKrAIBA...` |
| `DEV_ID_P12_PASSWORD` | Password for the .p12 (empty string if none) | `mysecretpw` |
| `APPLE_ID` | Your Apple ID email | `you@example.com` |
| `APPLE_TEAM_ID` | 10-character Team ID | `LE9Q47C92D` |
| `APPLE_APP_PASSWORD` | App-specific password for notarization | `xxxx-xxxx-xxxx-xxxx` |
| `SPARKLE_PRIVATE_KEY` | Sparkle EdDSA private key (from `generate_keys -x`) | `LS0tLS1CRU...` |
| `DEPLOY_KEY` | SSH private key for pushing to updates repo | `-----BEGIN OPENSSH...` |

## How to Release

Once setup is complete, releasing is simple:

```bash
# 1. Bump version in Xcode (MARKETING_VERSION in project settings)
# 2. Commit and push
git add -A && git commit -m "Bump version to 1.2.0" && git push

# 3. Create a GitHub Release
gh release create v1.2.0 \
  --title "ClawDeck v1.2.0" \
  --notes "## What's New
- Feature A
- Bug fix B
- Improvement C"
```

The workflow runs automatically:
- Builds → Signs → Notarizes → DMG → Uploads → Publishes appcast
- Users with ClawDeck installed get a native update prompt

## Adding Sparkle to the Xcode Project

If Sparkle isn't already added as a dependency:

1. Open `ClawDeck.xcodeproj` in Xcode
2. **File → Add Package Dependencies**
3. Search: `https://github.com/sparkle-project/Sparkle`
4. Version rule: **Up to Next Major** from `2.7.0`
5. Add the **Sparkle** product to the `ClawDeck` target

Then set the Info.plist:

1. Select the ClawDeck target
2. **Build Settings** → search `Info.plist`
3. Set **Info.plist File** to `ClawDeck/Info.plist`

## Troubleshooting

### "No shared scheme found"

CI needs a shared scheme. In Xcode:
**Product → Scheme → Manage Schemes → check "Shared"** next to ClawDeck.
Commit and push `ClawDeck.xcodeproj/xcshareddata/`.

### Notarization fails

- Check that `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_PASSWORD` are correct
- The app-specific password must be from the same Apple ID
- Hardened runtime must be enabled (the workflow sets `--options runtime`)

### "Developer ID Application" certificate not found

- Make sure you enrolled in the Apple Developer Program ($99/year)
- Create the certificate: Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application
- Export as .p12 and re-upload to GitHub secrets

### Sparkle update check does nothing

- Verify `SUFeedURL` in Info.plist points to the correct appcast URL
- Verify `SUPublicEDKey` matches the key from `generate_keys`
- Check that the appcast.xml is accessible at the URL (try in a browser)
