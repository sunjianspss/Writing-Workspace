# Releasing Creative Workshop Mac

Status: Active delivery contract

Owner role: Release engineer
Last verified: 2026-08-12

## Release classes

| Class | Purpose | Required identity | Distribution |
|---|---|---|---|
| Verified ad-hoc artifact | Internal QA and CI evidence | Ad-hoc signature | CI artifact or direct transfer between trusted developers |
| Public macOS release | End-user installation | Developer ID Application + notarization | Signed release channel |

The repository currently implements the first class. An ad-hoc artifact is not a public macOS release and must not be described as notarized.

## One-command internal package

```bash
./script/package_release.sh
```

The command runs the architecture guard and full Swift test suite, builds in release mode, assembles a temporary app bundle, writes version metadata from `VERSION`, copies SwiftPM resources, signs after all resources are present, performs positive and negative validation, and writes a versioned ZIP plus SHA-256 file under ignored `dist/`.

For a CI or otherwise monotonic build number:

```bash
BUILD_NUMBER=123 ./script/package_release.sh
```

`--skip-verify` is only for a local packaging retry after `./script/verify.sh` has already passed against the same tree. CI never uses it.

## Artifact contract

Every artifact must contain:

- `CFBundleShortVersionString` equal to `VERSION`;
- a numeric `CFBundleVersion`;
- the executable at `Contents/MacOS/CreativeWorkshopMac`;
- the SwiftPM resource bundle in the signed-app location `Contents/Resources`;
- a valid deep, strict code signature after resources are copied;
- a readable versioned ZIP and matching SHA-256 checksum.

`script/check_release.sh --self-test <app>` proves the validator rejects two mutated bundles: one with missing version metadata, and one whose `AppIcon.icns` was deleted and the bundle re-signed. The re-signing matters—without it that case would fail on the broken signature and prove nothing about the icon gate.

## Public-release gates not yet implemented

Before distributing outside trusted development channels:

1. Configure a Developer ID Application identity outside the repository.
2. Sign with hardened runtime and explicit entitlements.
3. Submit to Apple's notarization service and staple the ticket.
4. Verify Gatekeeper assessment on a clean supported macOS installation.
5. Record the release notes and immutable checksum.

Secrets, certificates and notarization credentials must never be committed. CI should receive them from protected secret storage only after the public-release workflow is deliberately introduced.
