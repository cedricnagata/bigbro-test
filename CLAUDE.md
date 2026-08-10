# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repository.

BigBroTest is a demo iOS app that exercises the whole [BigBroKit](https://github.com/cedricnagata/bigbro-kit)
feature set against a Mac running the BigBro daemon. It is not distributed publicly, but it does
deploy to TestFlight so the SDK can be exercised on real devices rather than the simulator.

See `README.md` for what the app does and how the model, voice and tool surfaces are laid out.

## TestFlight deploy pipeline

`.github/workflows/deploy-ios-testflight.yml` archives the app and uploads it to TestFlight.
It is a close copy of little-chef's, and the comments carried over with it are the record of
what four failed runs taught that project — read them before changing a step.

### Trigger

- **A PR merged into `main` carrying the `deploy-ios` label.** Gated on
  `github.event.pull_request.merged == true`, so closing a labelled PR without merging does
  nothing. Labels, not git tags — tags don't attach to merge events.
- **`workflow_dispatch`**, to redeploy the current `main` without inventing a commit.

`concurrency: testflight-ios` with `cancel-in-progress: false`, so two uploads can never race
for the same build number.

### Signing: manual, and why

This app has **one** signable target. The Tests/UITests bundle IDs still in `project.pbxproj`
are vestigial — `xcodebuild -list` reports a single target — so there is no extension needing
a second profile, and manual signing is the simpler and safer choice: CI never mutates the
Apple account.

The signing settings live in the **app target's Release config in `project.pbxproj`**, exactly
as little-chef does it:

```
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY = "Apple Distribution"
PROVISIONING_PROFILE_SPECIFIER = "NagataInc.bigbro-test"
```

That placement is load-bearing. `xcodebuild` build settings apply to **every target at once**,
and this project depends on BigBroKit through SPM — setting `PROVISIONING_PROFILE_SPECIFIER`
on the command line also hits the package target, which rejects it outright:

```
error: ... does not support provisioning profiles
```

**The consequence is local, and expected:** a *Release* archive on a developer's machine now
needs the `NagataInc.bigbro-test` profile installed, or Xcode fails with

```
No profile for team '...' matching 'NagataInc.bigbro-test' found
```

Debug builds — the simulator and device runs this app is normally used for — are untouched,
because only the Release config is pinned. Install the profile once (double-click the
downloaded `.mobileprovision`) and local archives work too. Deploying through the pipeline
rather than archiving by hand is the intended path regardless.

The provisioning profile must be an **explicit** App Store profile created in the developer
portal and named `NagataInc.bigbro-test`. An Xcode-managed profile is rejected by manual
signing (`error: Provisioning profile "X" is Xcode managed, but signing settings require a
manually managed profile`).

**Do not add `-allowProvisioningUpdates` or `-authenticationKey*` to the Archive step.** On
little-chef that made every archive ask Apple for an Apple Development certificate — an
account-global, capped mutation. The account hit the cap and every archive failed. The cap is
per-account, so doing it here would break little-chef too.

**Archive must not skip signing.** Entitlements live inside a code signature, so an unsigned
archive carries none, and `-exportArchive` re-signs from the bundle's existing entitlements
rather than reading them out of the profile.

### Build numbers

`CURRENT_PROJECT_VERSION = github.run_number + BUILD_NUMBER_OFFSET`, passed on the `xcodebuild`
command line (which outranks the project setting), with `manageAppVersionAndBuildNumber=false`
in the export options so nothing rewrites it.

Build numbers must **strictly increase within a `MARKETING_VERSION` train**. Set
`BUILD_NUMBER_OFFSET` (a repository *variable*) above the highest build already in TestFlight,
bump it after any manual upload, and reset it to `0` when `MARKETING_VERSION` moves. Failed runs
still consume run numbers; the sequence just skips.

### Secrets

Repository secrets, not environment secrets — the job declares no `environment:`, so
environment-scoped secrets would resolve to empty strings and fail confusingly mid-run.

| Secret | Scope | Shared with little-chef? |
|---|---|---|
| `APPLE_TEAM_ID` | account | yes |
| `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64` | account | yes |
| `IOS_DIST_CERT_P12_BASE64`, `IOS_DIST_CERT_PASSWORD` | certificate | yes |
| `IOS_PROFILE_APP_NAME`, `IOS_PROFILE_APP_BASE64` | this app | no — its own profile |

Plus repository **variable** `BUILD_NUMBER_OFFSET`.

Personal accounts have no org-level secrets, so the account-level values are copied per repo.
They are the *same values* as little-chef's: one Apple Distribution certificate signs every app
in the team. Reissuing that certificate invalidates every profile pinned to it, in **both**
repos — regenerate and re-upload all of them together.

### The kit revision is not pinned

This repo gitignores `*.resolved`, so it has no `Package.resolved` and BigBroKit resolves from
whatever `main` points at when CI runs. **A TestFlight build here is therefore not reproducible
from its commit** — the same commit deployed twice can ship different kit code.

That is deliberate for a test app whose job is exercising the latest kit, but it means a
misbehaving build cannot be traced from the commit alone. The workflow logs the resolved
revision for that reason. If reproducibility ever matters more than tracking `main`, stop
ignoring `*.resolved` and commit it, which is what little-chef does.

### First run

Don't test two things at once:

1. Merge the workflow **unlabelled** and expect a **skipped** run — the negative test of the
   `if:` gate, which also confirms the workflow registered.
2. Trigger `workflow_dispatch` from the Actions tab (only available once the file is on the
   default branch). Same code path, real upload, unambiguous failure.
3. Only then merge a labelled PR, which exercises the trigger.

The App Store Connect record must already exist. Creating it takes one manual archive and
upload from Xcode; until then the upload fails with `409 INVALID_APP_STATE`, minutes in, after
a perfectly good archive.

### When it fails

| Symptom | Cause |
|---|---|
| `altool` **401** | Bad/expired App Store Connect key, or wrong issuer |
| **409 `INVALID_APP_STATE`** | App record missing or removed in App Store Connect. **Not** a signing problem — check the bundle ID against the live record |
| **409 `VALIDATION_ERROR`**, "SDK version issue" | Runner's Xcode too old; the workflow pins `macos-26` and selects Xcode 26 for this reason |
| **409**, "bundle version must be higher" | `BUILD_NUMBER_OFFSET` too low |
| `error: ... is Xcode managed` at **Archive** | Managed profile + manual signing. Create an explicit profile |
| `error: ... doesn't include signing certificate` at **Archive** | Profile predates the certificate, or is bound to a different one. Regenerate it |
| `error: ... does not support provisioning profiles` | A signing setting was passed on the `xcodebuild` command line and hit the BigBroKit SPM target. Put it in the Release config instead |
| `No profile for team ... matching 'NagataInc.bigbro-test' found`, **locally** | Expected: the Release config pins that profile. Install it, or build Debug, which is unaffected |
| `security import` fails on empty input | Secrets set on an environment the job doesn't declare |
| **90022 / 90023 / 90713** at upload | App icon missing from the asset catalog — see below |

Inspect a run:

```sh
gh run view <id> --json jobs -q '.jobs[].steps[] | "\(.conclusion)\t\(.name)"'
gh run view <id> --log-failed
```

## Export compliance

`bigbro-test/Info.plist` declares `ITSAppUsesNonExemptEncryption = false`, which is what stops
App Store Connect asking the export-compliance question on every upload. Without it a build
sits in "Missing Compliance" until someone answers the form by hand, which defeats the point of
an automated deploy.

**`false` is the accurate answer here, not a shortcut to skip a dialog.** At the time it was
added, neither the app nor BigBroKit referenced CryptoKit, CommonCrypto, Security, or any
`https://` endpoint, and the transport is `NWConnection(to: endpoint, using: .tcp)` — plain TCP,
explicitly not `.tls`.

Re-check it if any of that changes — the protocol gaining TLS, or the app starting to talk to a
web service. Note the exemption is about *non-exempt* encryption: an app using only HTTPS through
the OS's own APIs still answers `false`, because that use is exempt. Verify with:

```sh
grep -rE "CryptoKit|CommonCrypto|SecKey|NWProtocolTLS|https://" bigbro-test/*.swift
```

The declaration lives in `Info.plist` rather than as an `INFOPLIST_KEY_*` build setting so it
sits beside `NSBonjourServices` and is greppable as one plain statement about the shipped app.

## App icon

`bigbro-test/Assets.xcassets/AppIcon.appiconset` holds a single 1024×1024 master,
`icon_1024.png` — the same mark the BigBro Mac app uses, copied from
`bigbro/app/Resources/Assets.xcassets/AppIcon.appiconset/`. `actool` derives every shipped size
from it.

Two constraints on that file, both of which Apple enforces at upload rather than at build:

- **Exactly 1024×1024 and no alpha channel.** Check with
  `sips -g pixelWidth -g pixelHeight -g hasAlpha icon_1024.png`.
- **The `Contents.json` entry must carry a `filename`.** An appiconset whose `Contents.json`
  lists sizes but no filenames compiles silently to nothing: no icons in the bundle and no
  `CFBundleIconName`, which Apple rejects as errors 90022 (missing 120×120), 90023 (missing
  152×152) and 90713 (missing `CFBundleIconName`) — three errors, one cause.

There is no top-level `CFBundleIconName` in the built `Info.plist` and that is correct.
`actool` writes it nested under `CFBundleIcons → CFBundlePrimaryIcon`, and little-chef — which
passes Apple's validator — is built the same way.

Verify a change without uploading:

```sh
xcodebuild build -project bigbro-test.xcodeproj -scheme bigbro-test \
  -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
# then, in the built .app:
#   AppIcon60x60@2x.png      must be 120x120
#   AppIcon76x76@2x~ipad.png must be 152x152
```
