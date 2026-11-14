# ObsidianScout Security Audit Report & Recommended Patches

**Audit Date:** 2026-11-13  
**Scope:**
- **Site (Server & Web Frontend)**: `Site/Obsidianscout-Java` (Kotlin / Ktor / Exposed / Vanilla JS)
- **App (Multi-Platform Client)**: `App/Obsidianscout-Java-App` (Flutter / Dart / Android / Windows / iOS / Web)

---

## Executive Summary & Findings Matrix

The codebase already implements many strong security controls (detailed in [Section 3](#3-existing-security-strengths-observed)). However, **17 actionable vulnerabilities** were identified across the server and client applications—including **2 Critical**, **6 High**, **6 Medium**, and **3 Low/Medium** findings.

| ID | Severity | Workspace | Component | Vulnerability Summary |
| :--- | :--- | :--- | :--- | :--- |
| **A1** | **CRITICAL** | App | `android/app/release.keystore`, `android/app/build.gradle.kts` | Production Android release signing keystore committed to Git with hardcoded credentials (`[REDACTED]`), enabling forged APK updates |
| **S1** | **CRITICAL** | Site | `IntegrationService.kt`, `ConfigRoutes.kt`, `SharedApiKeyService.kt` | SSRF, global API key exfiltration (`SharedApiKeyService`), and cross-team cache poisoning via `statboticsBaseUrl` and `match13BaseUrl` |
| **S2** | **HIGH** | Site | `MigrationService.kt`, `AdminRoutes.kt` | PostgreSQL JDBC URL injection (`socketFactory` / `sslfactory` RCE) & unsafe local SQLite path handling in DB migration tool |
| **S3** | **HIGH** | Site | `ProxyServer.kt`, `RateLimiter.kt` | Client IP spoofing via `CF-Connecting-IP` & `X-Forwarded-For` bypasses `LoginRateLimiter`, `LoginGuard`, `ThreatEngine`, and `BlockGate` |
| **S4** | **HIGH** | Site | `App.kt`, `redis-status.html`, `default-configs.html` | CSRF bypass on cookie-authenticated `/api/mobile/*`, `/api/cluster/*`, and `/api/security/admin/*` endpoints, presence-only `X-Cluster-Signature` check, and headerless `<form>` fallback |
| **S5** | **HIGH** | Site | `SnapshotService.kt`, `AdminRoutes.kt` | Arbitrary `.db` upload overwrites `cluster_secrets` (`session_secret`, `data_encryption_key`) without cache reload or validation |
| **A2** | **HIGH** | App | `app_update_service.dart`, `app_update_io.dart`, `AppUpdater.kt` | Self-updater executes downloaded binaries without verifying `checksums.txt` SHA-256, trusts size-matched files in shared `Downloads` folder, and skips Android APK signing cert checks |
| **A3** | **HIGH** | App | `auth_storage_service.dart`, `api_service.dart`, `AuthRoutes.kt` | Plaintext user password (`auth_password`) stored in `FlutterSecureStorage` / OS keychain and plaintext session cookie stored in `SharedPreferences` |
| **S6** | **MEDIUM** | Site | `MobileRoutes.kt` | Missing channel membership check in mobile chat reaction/edit/delete, private group takeover, and `chatEnabled` bypass |
| **S7** | **MEDIUM** | Site | `AuthRoutes.kt`, `PasskeyService.kt` | Missing rate limiting on passkey authentication endpoints (`PasskeyChallenges` table flood & user enumeration) and `http://` origin downgrade |
| **S8** | **MEDIUM** | Site | `BackupService.kt` | Team-scoped backups export user password hashes to team admins; global backups export live plaintext password reset tokens |
| **S9** | **MEDIUM** | Site | `GistUpdateService.kt`, `UpdateValidator.kt`, `UpdateHelper.kt`, `release.yml` | Server auto-updater treats SHA-256 checksums as optional when blank, does not restrict `downloadUrl` host, and release workflow lacked `checksums.txt` |
| **A4** | **MEDIUM** | App | `obsidian_barcode_modal.dart`, `qr_scanner_screen.dart` | Unbounded `zlib.decode` ("Zip Bomb" OOM crash) and unbounded `OSC:PART` multi-QR chunk allocation |
| **A5** | **MEDIUM** | App | `api_service.dart` | `setServerUrl` retains `_sessionCookie` across origin changes (leaking session cookie to new server) and `_verifySession` returns `true` on arbitrary exceptions |
| **S10** | **LOW/MED** | Site | `ClusterManagementService.kt` | Most node management methods send `X-Cluster-Signature` HMAC headers to `targetIp` without verifying `targetIp` is in the cluster roster |
| **S11** | **LOW/MED** | Site | `BannerRoutes.kt`, `BannerService.kt`, `AnalyticsRoutes.kt` | Cross-program (`FRC` vs `FTC`) banner modification by team admins, regex HTML sanitizer bypasses, and CSV formula injection |
| **A6** | **LOW/MED** | App | `AndroidManifest.xml`, `WidgetData.kt` | Android Auto Backup enabled by default, allowing unencrypted backup of `HomeWidgetPreferences` (`widget_token`), `SharedPreferences`, and `obsidianscout.sqlite` |

---

## 1. Site (`Obsidianscout-Java`) Vulnerabilities & Recommended Patches

### S1 [CRITICAL] — SSRF, Global API Key Exfiltration & Cross-Team Cache Poisoning via `statboticsBaseUrl` and `match13BaseUrl`

- **Affected Files**:
  - `Site/Obsidianscout-Java/src/main/kotlin/com/obsidianscout/routes/ConfigRoutes.kt`
  - `Site/Obsidianscout-Java/src/main/kotlin/com/obsidianscout/integrations/SettingsService.kt`
  - `Site/Obsidianscout-Java/src/main/kotlin/com/obsidianscout/integrations/SharedApiKeyService.kt`
  - `Site/Obsidianscout-Java/src/main/kotlin/com/obsidianscout/integrations/IntegrationService.kt`

#### Vulnerability Mechanics & Impact
1. **Server-Side Request Forgery (SSRF)**: Any team `ADMIN` (or custom role with `admin-settings`) could set `statboticsBaseUrl` and `match13BaseUrl` via `PUT /api/settings` or pass them directly to `POST /api/settings/test-api`. The server immediately issued HTTP requests to `${base}/v3/events` or `${base}/v1/frc/2026/events` without validating the scheme, hostname, or resolved IP address, enabling attacks against loopback services, cloud metadata (`169.254.169.254`), RFC1918 LAN targets, or Tailscale mesh nodes (`100.64.0.0/10`).
2. **Global API Key Exfiltration**: In `IntegrationService.kt` (`testApiKey` for `"match13"` and `fetchMatch13EventxPs`), when `request.match13Key` is `"********"` or blank, `SharedApiKeyService` falls back to the **server-wide shared key**. Pointing `match13BaseUrl` to an attacker-controlled URL exfiltrated the server's global Match 13 API key.
3. **Cross-Team Cache Poisoning**: `fetchStatboticsMatchEpaHistory` and `fetchMatch13MatchHistory` wrote responses fetched from custom URLs into `EpaOprHistoryCache` (keyed solely by `eventKey`), poisoning EPA/xP history for other teams.

#### Recommended & Applied Patch
Allow custom public HTTPS base URLs (for self-hosted mirrors or staging instances) while enforcing strict SSRF and credential isolation:
1. Validate URLs via `validateExternalApiBaseUrl(raw, defaultUrl, resolveDns)` in `SettingsService.kt`, rejecting non-`https://` schemes, userinfo, queries/fragments, localhost/`.local`/`.internal` hostnames, IP literals or DNS resolutions (`InetAddress.getAllByName`) pointing to loopback, RFC1918 site-local, link-local (`169.254.0.0/16`), CGNAT/Tailscale (`100.64.0.0/10`), multicast, or IPv6 ULA (`fc00::/7`) ranges.
2. Return `400 Bad Request` (`ApiException(HttpStatusCode.BadRequest, ...)`) in `ConfigRoutes.kt` when invalid URLs are submitted in `PUT /api/settings`, and re-validate with DNS resolution before every outbound fetch in `IntegrationService.kt`.
3. In `SharedApiKeyService.kt`, clear `shared.match13Key` fallback whenever `!isOfficialMatch13BaseUrl(settings.match13BaseUrl)`. Skip writing shared `EpaOprHistoryCache` entries when fetching from custom origins.

---

### S2 [HIGH] — PostgreSQL JDBC URL Injection & Unsafe SQLite File Handling in `MigrationService.kt`

- **Affected Files**:
  - `Site/Obsidianscout-Java/src/main/kotlin/com/obsidianscout/db/MigrationService.kt`
  - `Site/Obsidianscout-Java/src/main/kotlin/com/obsidianscout/routes/AdminRoutes.kt`

#### Vulnerability Mechanics & Impact
1. **PostgreSQL JDBC URL Injection**: Interpolating `pgConfig.host` and `pgConfig.database` directly into `"jdbc:postgresql://..."` allowed malicious parameters (`?socketFactory=...&socketFactoryArg=...`, `sslfactory=...`, `loggerFile=...`) leading to arbitrary Java class instantiation (RCE) or arbitrary file writes.
2. **Unsafe Local SQLite Path Handling**: Unvalidated `sqliteInstancePath` values could target UNC network shares (SMB credential leaks / hangs), symbolic links, or non-SQLite system files opened read-write. Restricting paths strictly to the app `data/` directory breaks legitimate migrations from external local backup directories (e.g., `/var/backups/...`).

#### Recommended & Applied Patch
1. Strictly validate PostgreSQL host (`^[a-zA-Z0-9.-]{1,253}$`), port (`1..65535`), and database name (`^[a-zA-Z0-9_-]{1,63}$`), passing credentials and SSL flags via `Properties` rather than query-string interpolation.
2. Allow local SQLite backup directories in `resolveSafeSqliteDir` while blocking null bytes, UNC/network paths (`\\`, `//`), and symbolic links (`Files.isSymbolicLink`), restricting filenames to the fixed `allowedSqliteDbFiles` allowlist, verifying the 16-byte `"SQLite format 3\u0000"` header (`validateSqliteFileHeader`), and opening the SQLite file read-only (`SQLiteConfig().apply { setReadOnly(true) }.toProperties()`).

---

### S3 [HIGH] — Client IP Spoofing via `ProxyServer.kt` and Unconditional `CF-Connecting-IP` Trust in `RateLimiter.kt`

- **Affected Files**:
  - `Site/Obsidianscout-Java/src/main/kotlin/com/obsidianscout/utils/ProxyServer.kt`
  - `Site/Obsidianscout-Java/src/main/kotlin/com/obsidianscout/auth/RateLimiter.kt`

#### Vulnerability Mechanics & Impact
1. `ProxyServer.kt` copied client-supplied `CF-Connecting-IP` and `X-Forwarded-For` headers and appended the remote IP to the end of `X-Forwarded-For`.
2. `ApplicationCall.clientIp()` in `RateLimiter.kt` trusted `CF-Connecting-IP` unconditionally from any trusted proxy and read the leftmost (attacker-controlled) entry of `X-Forwarded-For`, bypassing `LoginRateLimiter`, `LoginGuard`, and `BlockGate`.

#### Recommended Patch
1. In `ProxyServer.kt`, strip client-supplied `X-Forwarded-For`, `CF-Connecting-IP`, and `True-Client-IP` headers before writing `request.local.remoteAddress`.
2. In `RateLimiter.kt`, only trust `CF-Connecting-IP` when the immediate peer is a Cloudflare IP or `CloudflaredService` is running, and walk `X-Forwarded-For` right-to-left to select the rightmost untrusted hop.

---

### S4 [HIGH] — CSRF Protection Bypass on `/api/mobile/*`, `/api/cluster/*`, `/api/security/admin/*` and Headerless Form POSTs

- **Affected Files**:
  - `Site/Obsidianscout-Java/src/main/kotlin/com/obsidianscout/App.kt`
  - `Site/Obsidianscout-Java/src/main/resources/static/redis-status.html`
  - `Site/Obsidianscout-Java/src/main/resources/static/default-configs.html`

#### Vulnerability Mechanics & Impact
1. **Overbroad Path Exclusions**: Exempting `/api/mobile`, `/api/cluster`, and `/api/security/` skipped CSRF checks on cookie-authenticated endpoints.
2. **Presence-Only Cluster Header Bypass**: Checking `call.request.headers["X-Cluster-Signature"] != null` skipped CSRF even when the signature was invalid or spoofed.
3. **Headerless Form POST Fallback**: Falling back to hostname-only `Origin`/`Referer` comparison (ignoring scheme and port) weakened CSRF enforcement.

#### Recommended & Applied Patch
1. Verify cluster node-to-node signatures directly inside the CSRF interceptor (`call.request.headers["X-Cluster-Signature"] != null && call.hasValidClusterSignature()`, which caches verification results in `call.attributes[ClusterSignatureAccepted]` without triggering replay rejection in the route handler).
2. Exempt only genuinely public/webhook paths (`/api/security/unblock-request`, `/api/security/pow-challenge`, `/api/auth/slack/*`).
3. Ensure every web frontend `fetch` caller—including `http.js` (`Obsidianscout.request`), inline admin calls in `redis-status.html`, and fallback calls in `default-configs.html`—sends `'X-Requested-With': 'XMLHttpRequest'` / `X-CSRF-Token`.

---

### S5 [HIGH] — Arbitrary SQLite Snapshot Upload Overwrites `cluster_secrets` Without Cache Invalidation (`SnapshotService.kt`)

- **Affected Files**:
  - `Site/Obsidianscout-Java/src/main/kotlin/com/obsidianscout/routes/AdminRoutes.kt`
  - `Site/Obsidianscout-Java/src/main/kotlin/com/obsidianscout/db/SnapshotService.kt`

#### Vulnerability Mechanics & Impact
`SnapshotService.restoreFromDatabaseFile` copied all tables including `cluster_secrets` (`session_secret`, `data_encryption_key`, `vapid_private_key`), allowing a plant of known signing keys and desynchronizing in-memory key caches in `ClusterSecretService`.

#### Recommended Patch
Exclude `cluster_secrets` from snapshot restores by default (`tablesToMigrate.filterNot { it.equals("cluster_secrets", ignoreCase = true) }`).

---

### S6 [MEDIUM] — Missing Channel Authorization in Mobile Chat Reactions/Edits/Deletes, Group Lockout & `chatEnabled` Bypass

- **Affected Files**:
  - `Site/Obsidianscout-Java/src/main/kotlin/com/obsidianscout/routes/MobileRoutes.kt`

#### Vulnerability Mechanics & Impact
1. `editMessageInFiles`, `deleteMessageInFiles`, and `reactMessageInFiles` scanned all `*_chat_history.json` files without checking DM/group membership.
2. `POST /api/mobile/chat/groups` allowed overwriting membership for an existing open channel.
3. `/api/mobile/chat/*` did not check `getTeamSettings(...).chatEnabled`.

#### Recommended Patch
Enforce `chatEnabled`, reject group creation when history already exists, and verify channel membership (`team_chat_history.json`, `_group_chat_history.json`, `_dm_chat_history.json`) prior to reading or mutating messages.

---

### S7 [MEDIUM] — Missing Rate Limiting on Passkey Authentication (`AuthRoutes.kt`) & Origin Scheme Downgrade (`PasskeyService.kt`)

- **Affected Files**:
  - `Site/Obsidianscout-Java/src/main/kotlin/com/obsidianscout/routes/AuthRoutes.kt`
  - `Site/Obsidianscout-Java/src/main/kotlin/com/obsidianscout/auth/PasskeyService.kt`

#### Vulnerability Mechanics & Impact
1. `/api/auth/passkey/authenticate/begin` and `/finish` lacked `LoginRateLimiter`/`LoginGuard`, enabling `PasskeyChallenges` table flooding and account enumeration.
2. `PasskeyService.kt` allowed client-supplied `http://` origins for non-localhost RP IDs.

#### Recommended Patch
Apply `LoginRateLimiter` on passkey auth endpoints and restrict `http://` WebAuthn origins solely to `localhost` / `127.0.0.1`.

---

### S8 [MEDIUM] — Backup Export Leaks Password Hashes to Team Admins & Live Reset Tokens in Global Backups (`BackupService.kt`)

- **Affected Files**:
  - `Site/Obsidianscout-Java/src/main/kotlin/com/obsidianscout/db/BackupService.kt`

#### Vulnerability Mechanics & Impact
Team-scoped backups exposed `Users.passwordHash`, and global backups exported live plaintext `PasswordResetTokens`.

#### Recommended Patch
Redact `passwordHash` in team-scoped backups (preserving existing hashes on restore when blank) and omit `passwordResetTokens` from all backup exports.

---

### S9 [MEDIUM] — Server Auto-Updater Optional Checksum, Missing Release Checksums & Unrestricted Download Host (`GistUpdateService.kt`, `release.yml`)

- **Affected Files**:
  - `Site/Obsidianscout-Java/src/main/kotlin/com/obsidianscout/utils/GistUpdateService.kt`
  - `Site/Obsidianscout-Java/src/main/kotlin/com/obsidianscout/utils/UpdateValidator.kt`
  - `Site/Obsidianscout-Java/src/main/kotlin/com/obsidianscout/utils/UpdateHelper.kt`
  - `Site/Obsidianscout-Java/.github/workflows/release.yml`

#### Vulnerability Mechanics & Impact
`GistUpdateService` and `UpdateHelper` treated SHA-256 verification as optional when blank, `downloadFile` lacked an HTTPS GitHub domain allowlist, and `release.yml` did not automatically publish `checksums.txt`.

#### Recommended & Applied Patch
1. In `Site/Obsidianscout-Java/.github/workflows/release.yml`, run `sha256sum * > checksums.txt` in `release-artifacts` before `softprops/action-gh-release@v2` so every GitHub Release publishes `checksums.txt` alongside binaries.
2. In `UpdateValidator.kt`, require a valid 64-character hex SHA-256 checksum (rejecting blank hashes).
3. In `GistUpdateService.kt`, enforce `isTrustedUpdateUrl` (`https://` GitHub hosts) and automatically resolve the expected SHA-256 from Gist `sha256` -> GitHub Release asset `digest` -> the release's `checksums.txt` asset, avoiding manual Gist edits.

---

### S10 [LOW/MEDIUM] — Signed Cluster Request SSRF / HMAC Leak When `targetIp` Is Not Checked Against Cluster Roster

- **Affected File**:
  - `Site/Obsidianscout-Java/src/main/kotlin/com/obsidianscout/admin/ClusterManagementService.kt`

#### Vulnerability Mechanics & Impact
Cluster management requests sent `X-Cluster-Signature` HMAC headers to `targetIp` without verifying `targetIp` belongs to `getClusterNodes().nodes`.

#### Recommended Patch
Check `isRegisteredClusterNodeIp(targetIp)` before sending signed node management requests.

---

### S11 [LOW/MEDIUM] — Cross-Program Banner Modification, Regex HTML Sanitizer & CSV Formula Injection

- **Affected Files**:
  - `Site/Obsidianscout-Java/src/main/kotlin/com/obsidianscout/routes/BannerRoutes.kt`
  - `Site/Obsidianscout-Java/src/main/kotlin/com/obsidianscout/db/BannerService.kt`
  - `Site/Obsidianscout-Java/src/main/kotlin/com/obsidianscout/routes/AnalyticsRoutes.kt`

#### Recommended Patch
Force `targetProgram = session.program` for non-superadmin banner mutations, loop regex HTML sanitization until convergence, and escape leading `=`, `+`, `-`, `@`, `\t`, `\r` characters in CSV exports.

---

## 2. App (`Obsidianscout-Java-App`) Vulnerabilities & Recommended Patches

### A1 [CRITICAL] — Production Android Release Keystore Committed to Git with Hardcoded Credentials

- **Affected Files**:
  - `App/Obsidianscout-Java-App/android/app/release.keystore`
  - `App/Obsidianscout-Java-App/android/app/build.gradle.kts`
  - `App/Obsidianscout-Java-App/.gitignore`
  - `App/Obsidianscout-Java-App/.github/workflows/*`

#### Vulnerability Mechanics & Impact
`android/app/release.keystore` was committed to Git alongside hardcoded keystore credentials (`[REDACTED]`) in `build.gradle.kts`. Anyone with Git history access could sign a forged APK update using the same signing certificate.

#### Recommended & Incomplete-Remediation Note
1. Move signing credentials to untracked `android/key.properties` or CI GitHub Secrets / environment variables (`ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEYSTORE_ALIAS`), add `*.keystore`, `*.jks`, and `key.properties` to `.gitignore`, and untrack `release.keystore`.
2. **Important**: `git rm --cached android/app/release.keystore` only removes the file from future commits—the old keystore and `[REDACTED]` password remain in historical commits. Before making the repository public or trusting external contributors, rewrite history locally with `git filter-repo` (or BFG Repo-Cleaner), force-push intentionally, and rotate to a new production signing key (treating the old key as permanently compromised).

---

### A2 [HIGH] — Unverified Binary Execution, Shared `Downloads` Trust & Missing APK Signature Check (`app_update_service.dart`, `app_update_io.dart`, `AppUpdater.kt`)

- **Affected Files**:
  - `App/Obsidianscout-Java-App/lib/services/app_update_service.dart`
  - `App/Obsidianscout-Java-App/lib/services/app_update_io.dart`
  - `App/Obsidianscout-Java-App/android/app/src/main/kotlin/com/obsidianscout/obsidianscout_app/AppUpdater.kt`

#### Vulnerability Mechanics & Impact
1. `AppUpdateService` previously relied on byte-size equality instead of verifying SHA-256 checksums (`asset['digest']` / `checksums.txt`) and trusted pre-existing files of matching size in the shared `Downloads` directory.
2. `downloadPackage` lacked GitHub HTTPS host allowlisting.
3. Desktop `_installPortable` lacked Authenticode verification (`Get-AuthenticodeSignature`), and Android `AppUpdater.installApk` launched `Intent.ACTION_VIEW` without verifying that the downloaded APK's package name and signing certificate digest matched the installed application.

#### Recommended & Applied Patch
1. Resolve SHA-256 digests from GitHub asset metadata (`digest`) or `checksums.txt`, enforce HTTPS GitHub host allowlisting, download into app-private/verified storage, and check SHA-256 before trusting cached or downloaded packages.
2. On Windows (`_installPortable`), check `Get-AuthenticodeSignature` when signed.
3. On Android (`AppUpdater.kt`), verify `verifyApkSignature(activity, apkFile)` before invoking the installer intent: confirm `archiveInfo.packageName == activity.packageName` and compare SHA-256 digests of `signingInfo.apkContentsSigners` (API >= 28 `GET_SIGNING_CERTIFICATES`, `< P` `GET_SIGNATURES` fallback) against the running app's installed signing certificates.

---

### A3 [HIGH] — Plaintext Password Stored in `FlutterSecureStorage` & Session Cookie in `SharedPreferences`

- **Affected Files**:
  - `App/Obsidianscout-Java-App/lib/services/auth_storage_service.dart`
  - `App/Obsidianscout-Java-App/lib/services/api_service.dart`
  - `Site/Obsidianscout-Java/src/main/kotlin/com/obsidianscout/routes/AuthRoutes.kt`

#### Vulnerability Mechanics & Impact
1. `AuthStorageService` persisted the user's plaintext password (`auth_password`) alongside biometric enrollment.
2. `ApiService` duplicated the active `_sessionCookie` in unencrypted `SharedPreferences`.

#### Recommended Patch & Remaining Biometric UX Trade-off
1. Stop writing `_keyPassword` (`auth_password`) to `FlutterSecureStorage`, scrub legacy stored passwords on `loadCredentials()`, and store `_sessionCookie` solely in `FlutterSecureStorage`.
2. Slide-refresh active sessions on `GET /api/auth/status` (`call.requireSession()`) and sync renewed `Set-Cookie` headers into `AuthStorageService.updateJwt(...)` (`_keyJwt`), falling back to in-memory `_sessionPassword` when available during an active run.
3. **UX Limitation Note**: With plaintext password persistence removed, biometric unlock works across app lock/relaunch while the 30-day session cookie (`_keyJwt`) remains valid. After an explicit manual logout (which revokes the server session and deletes `_keyJwt`) or full 30-day inactivity expiration, password re-entry is required unless a dedicated revocable server-side biometric refresh token or mobile WebAuthn passkey flow is implemented.

---

### A4 [MEDIUM] — Unbounded Zlib Decompression ("Zip Bomb") & Unbounded Multi-Part QR Memory Allocation

- **Affected Files**:
  - `App/Obsidianscout-Java-App/lib/widgets/obsidian_barcode_modal.dart`
  - `App/Obsidianscout-Java-App/lib/screens/qr_scanner_screen.dart`

#### Vulnerability Mechanics & Impact
Unbounded `zlib.decode` and unbounded `OSC:PART:<index>:<total>` chunk counts allowed specially crafted QR codes to trigger OOM crashes.

#### Recommended & Applied Patch
1. Use bounded streaming decompression in `BarcodeCompressor.decompressData` with `RawZLibFilter.inflateFilter(windowBits: ZLibOption.defaultWindowBits, gzip: false, raw: false)` (matching `zlib.encode()` standard Zlib framing) and enforce a `512 * 1024` byte (512 KB) output ceiling plus compressed input size limit.
2. Validate `index` and `total` bounds (`1 <= index <= total <= 64`) in `qr_scanner_screen.dart`.

---

### A5 [MEDIUM] — Session Cookie Leaked Across Server Origin Changes & Permissive `_verifySession`

- **Affected Files**:
  - `App/Obsidianscout-Java-App/lib/services/api_service.dart`

#### Recommended Patch
Clear `_sessionCookie` and stored session state when `setServerUrl` switches to a different origin, allowlist parsed cookies, and return `false` when `_verifySession` encounters unexpected/invalid responses.

---

### A6 [LOW/MEDIUM] — Android Auto Backup Includes Unencrypted `HomeWidgetPreferences` & SQLite DB

- **Affected Files**:
  - `App/Obsidianscout-Java-App/android/app/src/main/AndroidManifest.xml`
  - `App/Obsidianscout-Java-App/android/app/src/main/kotlin/com/obsidianscout/obsidianscout_app/widgets/WidgetData.kt`

#### Recommended Patch
Set `android:allowBackup="false"` and `android:fullBackupContent="false"` in `AndroidManifest.xml`.

---

## 3. Existing Security Strengths Observed

During the audit, the following strong security practices were verified to be working well:
- **Password & Secret Cryptography**: Passwords use `scrypt` (`N=32768, r=8, p=1`) with transparent migration from legacy BCrypt/SHA-256 and constant-time comparison (`MessageDigest.isEqual`) in `AuthService.kt`. Slack bot tokens are encrypted at rest with AES-256-GCM (`ClusterSecretService.encryptSecret`).
- **Path Traversal Confinement**: `SafeFileUtils.kt` consistently enforces canonical path prefix checks (`resolveWithinDir`) across scouting data, chat history, robot images, and static documentation routes.
- **Image Upload Sanitization**: Robot image uploads in `ScoutingRoutes.kt` and `MobileRoutes.kt` validate magic bytes (`JPEG`, `PNG`, `GIF`, `WebP`) and strip EXIF/GPS metadata via `ImageMetadataStripper.stripMetadata`.
- **Layered Threat Detection**: `BlockGate`, `ThreatEngine`, `LoginGuard`, and `ProofOfWork` provide multi-tier brute-force, credential-stuffing, and path-scanner mitigation.
- **Frontend XSS Sanitization**: Web frontend views (`sanitizer.js`, `banners.js`, `chat.js`) use `DOMPurify` and `Sanitizer.escapeHtml`, and the Flutter client (`SanitizedBannerText`) parses banner markup into safe widget trees without executing HTML/JS.
