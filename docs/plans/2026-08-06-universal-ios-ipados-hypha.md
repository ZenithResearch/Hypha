# Universal iPhone and iPad Hypha Implementation Plan

> **For Hermes:** Use subagent-driven-development to implement this plan task-by-task with specification and code-quality review.

**Goal:** Ship one universal native Hypha app for iPhone and iPad that reuses the existing HyphaCore, Matrix Rust SDK adapter, E2EE store model, security flows, and SwiftUI design language without forking the macOS product.

**Architecture:** Keep one repository and one shared Swift/SwiftUI implementation. Preserve the current macOS bundle identity and app. Add a separate universal iOS/iPadOS application target that links shared `HyphaUI` and `HyphaCore` package products. Each installation remains a separate Matrix device and encrypted crypto store; cross-device trust is established through Matrix recovery and SAS rather than filesystem or Keychain sharing.

**Tech stack:** Swift 6-compatible SwiftPM sources, SwiftUI, Security.framework, Matrix Rust SDK Swift FFI, Xcode 26.4, iOS/iPadOS 18.0 minimum, macOS 26.4.

---

## Locked decisions

1. Build one universal Apple mobile app for iPhone and iPad—not separate phone and tablet codebases.
2. Keep it in this repository. Do not fork HyphaCore, Matrix adapters, security policy, or chat models.
3. Preserve the macOS bundle identifier `ca.zenithresearch.macos.client` and all existing macOS Keychain/session compatibility.
4. Use `ca.zenithresearch.ios.client` for the universal iPhone/iPad target.
5. The mobile app has its own account-scoped SDK databases and Keychain records. It must never copy or mount the Mac crypto store.
6. A mobile installation is a real additional Matrix device. Recovery and own-device verification must make that explicit.
7. Do not include the GitHub-source self-updater on iOS/iPadOS. Mobile builds are installed through Xcode/simulator initially and later through an explicitly approved Apple distribution path.
8. Preserve production fail-closed behavior: no plaintext fallback, no synthetic sessions, no credential logging, and no trust promotion from UI state alone.
9. No Android work in this initiative. Android remains a separate native-client decision because its trusted storage and lifecycle APIs differ.
10. Add no runtime UI or project-generation dependency. Commit a minimal Xcode project/workspace and keep SwiftPM as the shared-code authority.

## Current blockers and evidence

- `Package.swift:6` declares macOS only.
- `Vendor/MatrixRustSDK/MatrixSDKFFI.xcframework.zip` contains only `macos-arm64`; it cannot link an iPhone or simulator target.
- The SDK artifact must be rebuilt from the pinned Zenith fork commit `f4889ec898e77d8b8c9013adadd77f3d0901fc2d`, not the fork's newer `main`.
- `Sources/Hypha/HyphaApp.swift` imports AppKit, embeds `@main`, fixes the root to at least 760×520, uses `NSPasteboard`, and contains several desktop-width sheets.
- `Sources/Hypha/DesignSystem/Atoms/HyphaButton.swift` uses `NSCursor`.
- `Sources/Hypha/HyphaUpdateController.swift` is macOS-only by design.
- The current `NavigationSplitView` is reusable and can provide adaptive phone/tablet navigation after fixed desktop geometry is removed.

## Work-surface index

- **SDK artifact:** exact pinned Matrix fork, iOS device/simulator/macOS slices, generated Swift binding parity, provenance and licensing.
- **Shared application composition:** app model, root view, chat/security/admin surfaces, platform capability injection.
- **Responsive UI:** navigation, sheets, keyboard/safe area, compact and regular width behavior, touch targets.
- **Secure storage:** iOS Keychain accessibility, account-scoped SDK store paths, no Mac-store sharing.
- **Verification/recovery:** first-device bootstrap, additional-device recovery, SAS, incoming requests, contact verification.
- **Build/release:** local Xcode project, simulator builds, unsigned/free local development boundary.
- **QA:** iPhone and iPad simulator proof, macOS regression, live two-device Matrix evidence.

---

### Task 1: Freeze macOS and mobile identity boundaries in tests

**Objective:** Make it impossible for mobile work to silently migrate, share, or rename the existing macOS session and E2EE authority.

**Files:**
- Modify: `Tests/HyphaCoreTests/MatrixShellSourceContractTests.swift`
- Create: focused platform-storage identity tests under `Tests/HyphaCoreTests/`
- Read/lock: `Resources/Info.plist`, `Sources/HyphaCore/MatrixRustSDKChatService.swift`, `Sources/Hypha/HyphaApp.swift`

**Steps:**
1. Write fixtures for the existing macOS bundle ID, Keychain service, defaults suites, encrypted-envelope root, SDK crypto-store root, logger subsystem, and legacy migrations.
2. Write a separate iOS fixture with no overlapping bundle, Keychain, defaults, vault, crypto-store, or migration identity.
3. Assert no shared Keychain access group is introduced.
4. Assert logs and fixtures exclude tokens, passwords, registration tokens, recovery keys, SAS values, Matrix IDs, device IDs, event bodies, and transaction IDs.
5. Run the focused tests red before introducing the platform identity model.

**Stop condition:** Do not replace the SDK artifact until the preserved macOS and separate-mobile identity contract is executable.

### Task 2: Add a multi-platform MatrixSDKFFI artifact

**Objective:** Produce one checksummed XCFramework containing macOS arm64, iOS arm64, and iOS Simulator arm64 from the exact current Zenith SDK source authority.

**Files:**
- Modify: `Vendor/MatrixRustSDK/MatrixSDKFFI.xcframework.zip`
- Modify: `Vendor/MatrixRustSDK/PROVENANCE.md`
- Modify: `THIRD_PARTY_NOTICES.md`
- Modify: `Vendor/MatrixRustSDK/license-inventory.json` only if target resolution changes it
- Modify: release/verifier hashes that pin the artifact or provenance

**Steps:**
1. Create an isolated worktree at `f4889ec898e77d8b8c9013adadd77f3d0901fc2d`; do not move the active Matrix fork checkout from `main`.
2. Install only the required Rust targets: `aarch64-apple-darwin`, `aarch64-apple-ios`, and `aarch64-apple-ios-sim`.
3. Run the fork's `cargo xtask swift build-framework` with `--release`, the three explicit targets, `--ios-deployment-target 18.0`, and sequential builds.
4. Confirm the generated Swift sources are byte-identical to the currently reviewed bindings unless the target generator legitimately changes them; review any difference as an SDK API change.
5. Verify `Info.plist` slices, Mach-O platforms, minimum OS versions, architectures, linkability, checksum, and license inventory.
6. Replace the Git LFS artifact and update provenance with the exact command, source commit, target matrix, checksum, and test evidence.

**Verification:**
- `plutil -p` shows macOS, iOS, and iOS Simulator libraries.
- `swift test` remains green on macOS.
- A minimal iOS Simulator link probe imports `MatrixRustSDK` and constructs no fake runtime.

**Stop condition:** Do not start UI portability work if the exact pinned SDK cannot produce or link an iOS Simulator slice.

### Task 3: Parameterize platform persistence and data protection

**Objective:** Give macOS and iOS explicit, non-overlapping storage identities while preserving the current account-scoped vault architecture.

**Files:**
- Create: `Sources/HyphaCore/PlatformStorageIdentity.swift`
- Modify: `Sources/HyphaCore/MatrixRustSDKChatService.swift`
- Modify: `Sources/Hypha/HyphaApp.swift`
- Test: the platform identity tests introduced in Task 1

**Steps:**
1. Introduce an immutable platform storage identity containing bundle/defaults/logger/Keychain/vault/crypto-root values and legacy-migration policy.
2. Inject it into `MatrixEncryptedSessionVault`, `MatrixRustLiveClientFactory`, and `MatrixAppModel` rather than reading macOS literals globally.
3. Make the macOS configuration reproduce every current persisted string byte-for-byte and retain all legacy migration behavior.
4. Make the iOS configuration use `ca.zenithresearch.ios.client` namespaces and disable macOS legacy migration.
5. Store iOS vault roots, SDK store keys, and saved local credentials with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and explicit `kSecAttrSynchronizable = false`. Preserve the existing macOS `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` behavior byte-for-byte.
6. Apply `FileProtectionType.complete` (`NSFileProtectionComplete`) to the iOS vault directory, each encrypted envelope, the Matrix SQLite directory, database files, `-wal`/`-shm` sidecars, and SDK-created cache files. Keep first-release synchronization foreground-only.
7. Add attribute-level tests after creation, encrypted-envelope atomic replacement, relaunch, SDK initialization, and the first sync that creates SQLite sidecars. Path-only assertions are insufficient.
8. Verify account removal remains account-scoped and neither platform can discover or open the other platform's store.

### Task 4: Split shared UI from platform entry points

**Objective:** Make the product UI a reusable package library while preserving the existing macOS app behavior and identity.

**Files:**
- Modify: `Package.swift`
- Modify: `Sources/Hypha/HyphaApp.swift`
- Create: `Sources/HyphaMac/HyphaMacApp.swift`
- Move or conditionally compile: `Sources/Hypha/HyphaUpdateController.swift`
- Test: `Tests/HyphaCoreTests/MatrixShellSourceContractTests.swift`

**Steps:**
1. Write a failing source-contract test requiring `.iOS(.v18)`, a `HyphaUI` library, a preserved macOS product, and separate platform entry points.
2. Convert the existing `Sources/Hypha` implementation into `HyphaUI` without exposing internal model types unnecessarily.
3. Expose one narrow `public HyphaRootView` composition surface that creates the production `MatrixAppModel` internally.
4. Move `@main` and macOS window geometry to `HyphaMacApp.swift`.
5. Keep the updater and AppKit lifecycle available only on macOS.
6. Build the macOS package and packaged app, verify bundle identifier, source receipt, Keychain service, and signature remain unchanged.

**Verification:**
- `swift test`
- `swift build -c release --product Hypha`
- `./build-app.sh`
- Existing saved-account restore still works in `/Applications/Hypha.app`.

### Task 5: Establish platform capability seams

**Objective:** Remove direct AppKit coupling from shared UI without weakening product behavior.

**Files:**
- Modify: `Sources/Hypha/HyphaApp.swift`
- Modify: `Sources/Hypha/DesignSystem/Atoms/HyphaButton.swift`
- Modify: `Sources/Hypha/Auth/HyphaAuthenticationViews.swift`
- Create: `Sources/Hypha/HyphaPlatformCapabilities.swift`
- Test: new platform/source-contract tests under `Tests/HyphaCoreTests/`

**Steps:**
1. Introduce a small capability value for clipboard, application update availability, pointer cursor behavior, and platform-specific password-saving availability.
2. Use `NSPasteboard` on macOS and `UIPasteboard` on iOS behind the capability boundary.
3. Keep `NSCursor` push/pop code macOS-only; preserve hover styling for iPad pointer support without AppKit.
4. Render checkbox style on macOS and an appropriate native toggle on compact touch devices.
5. Keep the shared UI free of unconditional `import AppKit` and `NS*` symbols.
6. Verify secrets remain cleared before awaited work and are not copied into capability state.

### Task 6: Add the universal iOS/iPadOS application target

**Objective:** Produce a real simulator-installable `.app` that links the shared package products.

**Files:**
- Create: `HyphaMobile.xcodeproj/project.pbxproj`
- Create: `Sources/HyphaMobile/HyphaMobileApp.swift`
- Create: `Resources/iOS/Info.plist`
- Create: `Resources/iOS/HyphaMobile.entitlements`
- Create: `Resources/iOS/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: iOS icon renditions derived from `Resources/ZenithOSIcon.svg`
- Create: `scripts/build-ios-simulator.sh`
- Modify: `.github/workflows/ci.yml`
- Modify: `README.md`

**Steps:**
1. Write a failing project/source contract for the universal device family `[1, 2]`, bundle identifier, network capability, and local package products.
2. Add a minimal application target with no duplicated Matrix or app-model source files.
3. Link `HyphaUI` and its transitive `HyphaCore`/`MatrixRustSDK` dependencies.
4. Configure iOS 18.0, iPhone+iPad, portrait and landscape support, and no source updater.
5. Generate canonical app icons from the existing Zenith/Hypha SVG; do not invent a second mark.
6. Add a deterministic simulator build script using Xcode 26.4 and a clean DerivedData path.
7. Add a required mobile CI job that builds the committed project for iPhone and iPad simulator destinations, verifies `UIDeviceFamily` contains `1` and `2`, verifies `ca.zenithresearch.ios.client`, and fails on package-link or target drift.
8. Keep TestFlight/App Store archive, upload, and publishing steps absent from CI until separately authorized.
9. Build without requiring a paid Apple team or persistent signing credential.

**Verification:**
- `xcodebuild -project HyphaMobile.xcodeproj -scheme HyphaMobile -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' CODE_SIGNING_ALLOWED=NO build`
- `simctl install` and `simctl launch` succeed.
- Built app bundle identifier is `ca.zenithresearch.ios.client`.

### Task 7: Make the shell responsive

**Objective:** Preserve the existing visual language while making every primary flow usable at compact iPhone and regular iPad widths.

**Files:**
- Modify: `Sources/Hypha/HyphaApp.swift`
- Modify: `Sources/Hypha/MatrixAdminSheet.swift`
- Modify: `Sources/Hypha/Auth/HyphaAuthenticationViews.swift`
- Modify: `Sources/Hypha/HyphaSecurityBanner.swift`
- Modify: `Sources/Hypha/Chat/HyphaChatMessageRow.swift` only where compact wrapping requires it
- Add focused layout-policy tests under `Tests/HyphaCoreTests/`

**Steps:**
1. Introduce compact/regular layout policy from SwiftUI size classes; do not read raw device model names.
2. Remove unconditional root minimum width/height outside macOS.
3. Let `NavigationSplitView` collapse to stack navigation on iPhone and remain two/three-column on iPad.
4. Replace fixed 430/500/560/640-point sheet widths with `maxWidth` and platform-specific presentation behavior.
5. Put long recovery, security, and admin content in bounded scroll regions with safe-area-aware keyboard behavior.
6. Preserve at least 44×44-point touch targets and VoiceOver labels.
7. Keep the composer and send button visible above the software keyboard and preserve unsent drafts across navigation.
8. Run an executable matrix on iPhone 17 Pro portrait/landscape, compact iPhone 17e portrait/landscape, iPad Pro 13-inch portrait/landscape, and deterministic 600-point and 500-point iPad Split View host widths.
9. At every required width, assert root/sheet containment, 44×44 minimum interactive frames, a passing XCTest accessibility audit, and no clipped Dynamic Type content.
10. Type through the software-keyboard path and assert the composer/send control remains visible, drafts survive navigation, and focus follows established product behavior.
11. Exercise Security Center, recovery setup/restore, first-device password continuation, invitation/new-room sheets, password change, and every administration sheet in the same matrix.

### Task 8: Verify secure mobile persistence

**Objective:** Prove that mobile sessions and crypto stores persist securely and remain device-scoped.

**Files:**
- Modify as required: `Sources/HyphaCore/MatrixSDKSessionVault.swift`
- Modify as required: `Sources/HyphaCore/HyphaMatrixCredentialStore.swift`
- Test: mobile-specific security integration tests
- Document: `docs/security-model.md`, `docs/architecture.md`, `README.md`

**Steps:**
1. Verify Application Support URLs and account-scoped database paths under the iOS app container.
2. Assert iOS Keychain items use exactly `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `kSecAttrSynchronizable = false`, and the default app access boundary.
3. Preserve optional Apple Passwords behavior only when the platform capability and associated-domain contract are actually configured; otherwise render it unavailable rather than accepting secrets into a dead path.
4. Assert vault files, SQLite databases, WAL/SHM sidecars, and cache files remain `NSFileProtectionComplete` after creation, replacement, relaunch, SDK initialization, and sync.
5. Prove app termination/relaunch restores the session and decrypts a fresh post-join event.
6. Prove deleting one local account removes only that account's session/store/credential records.
7. Document that Mac and mobile are separate Matrix devices and stores.

### Task 9: Complete cross-device verification needed by mobile onboarding

**Objective:** Make Mac ↔ iPhone/iPad verification a complete product-owned flow rather than relying on another Matrix client.

**Files:**
- Modify: `Sources/HyphaCore/MatrixChatService.swift`
- Modify: `Sources/HyphaCore/MatrixRustSDKChatService.swift`
- Modify: `Sources/HyphaCore/HyphaChatMessagePresentation.swift`
- Modify: `Sources/Hypha/HyphaSecurityBanner.swift`
- Modify: `Sources/Hypha/Chat/HyphaChatMessageRow.swift`
- Add verification coordinator and tests in `Sources/HyphaCore/` and `Tests/HyphaCoreTests/`

**Steps:**
1. Expand the verification automaton with incoming request, acknowledged, accepting, SAS start, challenge, approving, finished, cancelled, failed, and timed-out states.
2. Install and retain the verification controller/delegate before continuous sync.
3. Implement incoming own-device requests using acknowledge + accept + SAS.
4. Keep outgoing own-device requests and add bounded phase timeouts and idempotent terminal settlement.
5. Preserve canonical Matrix `senderID` plus typed contact-verification eligibility/action in `HyphaChatMessagePresentation`; never derive authority from a display name.
6. Add a verification callback to `HyphaChatMessageRow`, route it through `MatrixCompanionShell` and `MatrixAppModel`, then call `requestUserVerification(userId:)` through the service boundary.
7. Expose the action only for eligible `.unverifiedIdentity` events when the current own identity is authoritative. Unknown/unsigned devices, violations, and unavailable identity state remain non-actionable.
8. Refresh authoritative contact identity and affected timeline authenticity after completion; never clear warnings optimistically.
9. Add restart/cancellation behavior and tests for duplicate/late callbacks.

**Verification:**
- Mac initiates → iPhone accepts → both compare → both approve → fresh trust query confirms.
- iPhone initiates → iPad accepts with the same outcome.
- Contact verification clears a fresh sender-identity warning only after SDK confirmation.
- Tests prove the canonical sender ID reaches the command path, display names cannot substitute for it, and ineligible warnings remain non-actionable.
- Mismatch, cancel, timeout, remote cancel, and duplicate terminal callback tests pass.

### Task 10: Run responsive and E2EE acceptance gates

**Objective:** Produce evidence that the universal mobile app is usable and cryptographically correct on both form factors.

**Files:**
- Create: `docs/evidence/mobile/README.md`
- Create: safe simulator test scripts as needed
- Update: `release/encryption-gate.json` only after a fresh production proof on the exact candidate commit

**Steps:**
1. Run full macOS tests/build/signature regression.
2. Run the complete Task 7 portrait/landscape/Split View matrix with machine assertions—not screenshots alone.
3. Functionally exercise every administrator operation with safe fake/local authority: account actions, room/Space operations, destructive confirmations, password-reset, keyboard/scrolling, in-flight/failed/success states, and secret clearing. Live destructive production mutations remain separately user-gated.
4. Capture app-only simulator evidence for homeserver, login, room list, room, composer/keyboard, security center, recovery, verification, and admin layouts.
5. Run a disposable two-account production Matrix proof for mobile encrypted send/decrypt and restore without logging content or identifiers.
6. Run a human-compared Mac ↔ mobile SAS proof and verify authoritative trust on both sides.
7. Confirm temporary accounts/rooms are cleaned up.
8. Scan safe logs and test output to prove that tokens, passwords, registration tokens, recovery keys, SAS values, Matrix IDs, device IDs, event bodies, and transaction IDs were not emitted.
9. Update docs with exact proven and unproven distribution boundaries.

**Physical-device gate:** Simulator completion may be called `simulator-ready` only. Before any `device-ready`, beta, or mobile-release claim, obtain explicit authorization for a development team and physical devices, install a development-signed build on one iPhone and one iPad, and repeat Keychain/file-protection (including SQLite sidecars), termination/relaunch persistence, software-keyboard/lifecycle, incoming/outgoing SAS, recovery, encrypted round-trip, and account-switching checks. If signing/team/device access is unavailable, record the gate as unproven.

**Release boundary:** Simulator/source builds do not require Apple Developer Program membership. Physical local installation can use an explicitly selected development team. TestFlight/App Store distribution remains a separate user-approved paid-Apple gate and must not be implied by simulator success.

---

## Acceptance criteria

- One shared codebase produces the existing macOS app and one universal iPhone/iPad app.
- No feature uses a mock Matrix service in production composition.
- Mac bundle identity and saved-session compatibility are unchanged.
- iPhone and iPad use separate encrypted Matrix device stores.
- Authentication, room navigation, encrypted timeline, sending, account switching, recovery, and verification render without horizontal overflow on phone and tablet.
- Every existing administration operation has functional compact and regular-width acceptance, including destructive confirmation, password reset, scrolling, keyboard, state, and secret-clearing behavior.
- Incoming and outgoing Hypha-to-Hypha SAS complete with authoritative post-finish trust confirmation.
- The screenshot-level sender identity warning has a real contact-verification path rather than guidance-only copy.
- Mac tests/build/signing and mobile simulator builds are green.
- Required CI builds iPhone and iPad simulator destinations and verifies universal device-family and bundle metadata.
- Simulator evidence is labeled `simulator-ready`; physical iPhone+iPad evidence is mandatory before `device-ready` or release claims.
- Public distribution claims remain honest about signing, provisioning, and Apple program requirements.

## Non-goals

- Android.
- Sharing a live Matrix crypto database between Mac and mobile.
- Replacing Matrix with Dregg or secS authority.
- App Store/TestFlight publication in the initial implementation.
- A custom cryptographic implementation.
- Mobile execution of the GitHub source updater.
