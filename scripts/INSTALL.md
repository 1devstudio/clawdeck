# Installing ClawDeck

## First Launch

After downloading and unzipping, macOS may block the app because it's not from the App Store.

### If you see "ClawDeck is damaged and can't be opened"

Open **Terminal** and run:

```bash
xattr -cr ~/Downloads/ClawDeck.app
```

(Adjust the path if you unzipped somewhere else.)

Then double-click ClawDeck.app to launch.

### If you see "ClawDeck can't be opened because it is from an unidentified developer"

1. **Right-click** (or Control-click) on ClawDeck.app
2. Click **Open**
3. Click **Open** again in the dialog

macOS remembers your choice — subsequent launches work normally.

## Connecting

You'll need your Clawdbot gateway details:
- **Host** — your server's domain (e.g. `gateway.example.com`)
- **Port** — `443` for TLS
- **Token** — your gateway auth token

Ask your Clawdbot agent: *"What's my gateway URL and auth token for ClawDeck?"*
