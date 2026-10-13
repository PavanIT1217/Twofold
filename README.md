# Twofold

An encrypted family vault for the things your family would need: passwords, insurance policies, property papers, bank accounts, IDs and "who do I call" details.

- **Encrypted on the phone.** Argon2id, X25519 and XChaCha20-Poly1305 from libsodium.
- **Shared only with people you pair with in person**, by scanning each other's QR codes. Made for couples, with room for up to six family members (Owner, Editor and Viewer roles).
- **No servers and no data collected.** Phones sync directly over home Wi-Fi. Each person can keep an encrypted backup in their own Google Drive app folder, or save a backup file.

Website: **https://twofold.webappslab.com**

## What the app does

| Area | Features |
|---|---|
| Setup | Create a vault, or join one; master password; printable recovery kit (PDF); restore from Google Drive or a backup file |
| Unlock | Master password, recovery key, or fingerprint / face (key kept in Android Keystore / iOS Keychain) |
| Vault | 16 templates (insurance, property, bank, locker, deposits, investments, IDs, vehicles, loans, contacts, logins, notes, "Read this first"), custom fields, "What to do" notes, pinning, search, categories, trash with 30-day retention |
| Documents | Scan with the camera, add photos or files; encrypted per file; viewed in memory (images, PDFs) |
| Reminders | "Coming up" list on the home screen; notifications 30, 7 and 1 days before a date, never showing private details |
| Family | Pair by scanning each other's QR codes and comparing a pair number; roles; remove a member (moves the vault to a new key) |
| Sync | Paired phones find each other on the Wi-Fi (Bonjour/mDNS) and sync over an encrypted, mutually authenticated connection; simultaneous edits keep both versions |
| Backup | Encrypted backup to the Google Drive app-data folder (daily, automatic once on), or an encrypted backup file |
| Hardening | Auto-lock, screenshots and app-switcher previews blocked, clipboard cleared after 30 seconds, Android OS backup of app data turned off |

## Repository

| Folder | What's in it |
|---|---|
| `app/lib/core/crypto/` | Password key, recovery key, identities, vault keys, item and file encryption, pairing fingerprints |
| `app/lib/data/` | Item templates, models, version vectors, keyring, on-disk store, the `Vault` (items, members, merging) |
| `app/lib/sync/` | Encrypted channel between phones, sync protocol, Wi-Fi discovery, pairing codes |
| `app/lib/backup/` | Backup file format, Google Drive app-data backup |
| `app/lib/services/` | Fingerprint unlock, reminders, recovery kit PDF, clipboard and screenshot guards |
| `app/lib/app/` | `AppController`: setup, lock/unlock, family, sync, backup |
| `app/lib/ui/` | Screens |
| `app/test/` | Tests for crypto, the vault, sync over real sockets, the app controller and reminders |
| `website/` | Static website. No trackers, web fonts or third-party requests. |
| `.github/workflows/` | `app.yml` checks formatting, analysis and tests and builds an Android APK; `website.yml` checks the website's SEO basics and publishes `website/` to GitHub Pages |

## Run the app

```sh
cd app
flutter pub get
flutter test
flutter run
```

libsodium is built and bundled automatically by the `sodium` package's build hooks (the first build takes a few minutes). Gradle downloads a Java 17 toolchain if a plugin needs one.

## How the encryption fits together

```text
master password ──Argon2id──▶ password key ─┐
recovery key (printed kit) ─────────────────┴─▶ unlocks identity (X25519 key pair)
identity ──opens──▶ vault key (sealed separately for each member, per key version)
vault key ──wraps──▶ item keys / file keys ──▶ items / attachments
```

Every encrypted blob is bound to what it belongs to (vault, item, version, key version), so data copied, swapped or replayed elsewhere is rejected. The vault's member list is itself an encrypted record.

**Sync.** Two paired phones open a TCP connection on the local network and run a handshake that mixes four X25519 results (ephemeral and static keys on both sides). Only the two paired phones can derive the session keys, which are fresh each time. Then each side sends the version vector of every record, asks for what it is missing, and merges. If two people edited the same item, every phone picks the same winner and keeps the other version as a "conflict copy".

**Roles** are enforced by the app: phones ignore item changes authored by a viewer. Every member holds the vault key, so roles are a safeguard against mistakes, not against a member who modifies the app.

See `website/security.html` for the plain-language version.

## Setting up Google Drive backup

Backups use the `drive.appdata` scope (Twofold's own hidden folder only). Before release, in [Google Cloud Console](https://console.cloud.google.com/):

1. Create a project and enable the **Google Drive API**.
2. Set up the **OAuth consent screen** (app name Twofold, privacy policy `https://twofold.webappslab.com/privacy.html`) and add the scope `https://www.googleapis.com/auth/drive.appdata`. It's a non-sensitive scope, so only basic brand verification is needed.
3. Create OAuth client IDs:
   - **Android**: package `com.webappslab.twofold` and the SHA-1 of your signing key (`keytool -list -v -keystore <keystore>`). Add one for the debug key too while testing.
   - **iOS**: bundle ID `com.webappslab.twofold`. Then add to `app/ios/Runner/Info.plist` the `GIDClientID` key (the iOS client ID) and a URL type whose scheme is the reversed client ID. Without this, turning on backup on iPhone will fail.
   - **Web**: pass it to the build with `--dart-define=GOOGLE_SERVER_CLIENT_ID=<web client id>`.

Saving a backup file works without any of this.

## Website and search

Every page has a unique title and description, a canonical URL, Open Graph and Twitter cards (with `assets/og-image.jpg`) and schema.org structured data: `WebSite`, `Organization`, `MobileApplication` and `FAQPage` on the home page, `Article` or `TechArticle` and breadcrumbs on the others. `robots.txt`, `sitemap.xml`, `site.webmanifest`, icons and a `404.html` are in `website/`. `checklist.html`, a family emergency information checklist, is the page written to bring in search traffic.

`.github/scripts/check_website.py` runs on every pull request that touches the website. It fails if a page is missing a title, description, canonical URL, social card or structured data, if a link or anchor is broken, or if the sitemap doesn't match the pages. When you add a page, add it to `sitemap.xml` and give it the same `<head>` as the others.

After the site is live:

1. Add the site to [Google Search Console](https://search.google.com/search-console) as a domain property (verify with a DNS TXT record on `webappslab.com`, so no file or tag is needed), then submit `https://twofold.webappslab.com/sitemap.xml`. Do the same in [Bing Webmaster Tools](https://www.bing.com/webmasters), which can import from Search Console.
2. Check the home page with the [Rich Results Test](https://search.google.com/test/rich-results) and a link preview in WhatsApp or Slack.
3. Once the apps are in the stores: swap the "Soon" buttons for store links, add the store URLs to `sameAs` and `installUrl` in the home page's `MobileApplication` data along with the price (`offers`), and add `<meta name="apple-itunes-app" content="app-id=…">` for Safari's app banner.
4. When you update a page, change its `lastmod` in `sitemap.xml` and its `dateModified`.

## Before release

- Replace the `support@example.com` placeholder in `website/privacy.html`, `terms.html` and `support.html` with the real contact address.
- Android release signing: create an upload key and a `signingConfigs.release` in `app/android/app/build.gradle.kts` (it uses the debug key for now).
- App icons and store screenshots.
- Store privacy labels: no data collected. App Store export compliance: the app uses standard encryption (libsodium) to protect user data.
- The app ID is `com.webappslab.twofold` on Android and iOS.

## Roadmap

| Milestone | Scope | Status |
|---|---|---|
| M1 | Crypto core and tests | ✅ |
| M2 | Onboarding, recovery kit, unlock (password, recovery key, biometrics), templates, encrypted storage, reminders | ✅ |
| M3 | Pairing (QR and pair number), home Wi-Fi sync, roles, conflict copies, removing members | ✅ |
| M4 | Backup and restore (Google Drive app folder, backup file) | ✅ |
| M5 | Attachments and hardening | ✅ |
| M6 | Store release: signing, icons, Google OAuth clients, store listings | |
| Later | Emergency access, iCloud backup, sync through a shared cloud folder | |
