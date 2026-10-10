# Twofold

An encrypted family vault for the things your family would need: passwords, insurance policies, property papers, bank accounts, IDs and "who do I call" details.

- **Encrypted on the phone.** Argon2id, X25519 and XChaCha20-Poly1305 from libsodium.
- **Shared only with people you pair with in person**, by scanning each other's QR code. Made for couples, with room for up to six family members (Owner, Editor and Viewer roles).
- **No servers and no data collected.** Phones sync directly over home Wi-Fi, and each person keeps an encrypted backup in their own Google Drive app folder or iCloud.

## Repository

| Folder | What's in it |
|---|---|
| `app/` | Flutter app for Android and iOS |
| `app/lib/core/crypto/` | The crypto core: password key, recovery key, identities, vault keys, items, attachments, pairing fingerprints |
| `website/` | Static website (home, security, privacy, terms, support). No trackers, fonts or third-party requests. |
| `.github/workflows/` | `app.yml` checks formatting, analysis and tests; `website.yml` publishes `website/` to GitHub Pages from `main` |

## Run the app

```sh
cd app
flutter pub get
flutter test      # crypto and widget tests
flutter run
```

libsodium is built and bundled automatically by the `sodium` package's build hooks.

## Publish the website

In the repository on GitHub: **Settings → Pages → Build and deployment → Source: GitHub Actions**. Every push to `main` that changes `website/` then publishes it. To use your own domain, add a `website/CNAME` file containing the domain and set up DNS.

## How the encryption fits together

```text
master password ──Argon2id──▶ password key ─┐
recovery key (printed kit) ─────────────────┴─▶ unlocks identity (X25519 key pair)
identity ──opens──▶ vault key (sealed separately for each member)
vault key ──wraps──▶ item keys / file keys ──▶ items / attachments
```

Every encrypted blob is bound to what it belongs to (vault, item, version, key version), so data copied, swapped or replayed elsewhere is rejected. See `website/security.html` for the plain-language version.

## Roadmap

| Milestone | Scope | Status |
|---|---|---|
| M1 | Crypto core and tests | ✅ |
| M2 | Single-phone vault: onboarding, recovery kit, biometric unlock, item templates, encrypted local database, reminders | |
| M3 | Pairing (QR and fingerprint check) and home Wi-Fi sync, roles, conflict copies | |
| M4 | Personal backup and restore (Drive app folder / iCloud) | |
| M5 | Attachments and hardening (auto-lock, screenshot block, clipboard clear, encrypted export) | |
| M6 | Store release | |

## Before release

- Replace the `support@example.com` placeholder in `website/privacy.html`, `terms.html` and `support.html` with the real contact address.
- The app ID is `app.twofold.twofold` on both Android and iOS. It can't be changed after the first store release, so change it now if you want a different one.
