# Release Checklist

This checklist is the single runbook for reproducing a SoloPM public alpha release.

## Preconditions

- Release branch is cut from `develop`.
- `security find-identity -p codesigning -v` shows a Developer ID Application identity.
- `packaging/signing.env` exists only on the release machine.
- `packaging/notarization.env` exists only on the release machine.
- Sparkle private key exists in Keychain.
- `SOLOPM_SPARKLE_FEED_URL` and `SOLOPM_SPARKLE_PUBLIC_ED_KEY` are set for release builds.
- `SOLOPM_CLEAN_ENV_LAUNCH_CONFIRMED=1` is set only after a clean-user install and launch check.
- `SOLOPM_LOGIN_ITEM_TOGGLE_CONFIRMED=1` is set only after Settings can toggle launch at login in a signed app.

## Order

1. test

```bash
swift test
```

2. build

```bash
SOLOPM_BUILD_CONFIGURATION=release ./script/build_and_run.sh --build-only
```

3. sign

```bash
./script/verify_signing_setup.sh
./script/sign_app.sh
```

4. notarize

```bash
./script/notarize_app.sh
```

5. release environment preflight

```bash
SOLOPM_RELEASE_PREFLIGHT_ONLINE=1 ./script/verify_release_environment.sh
```

6. package

```bash
./script/package_release.sh
```

7. checksum

```bash
cat dist/releases/*.sha256
```

8. appcast

```bash
./script/generate_appcast.sh
./script/verify_appcast.sh packaging/appcast.sample.xml
```

9. final readiness report

```bash
./script/release_readiness_report.sh
```

10. tag

```bash
git tag -a v0.1.0-alpha.1 -m "SoloPM 0.1.0 alpha 1"
```

11. release notes

Use [public-alpha.md](public-alpha.md) as the base. Include artifact names, checksums, supported macOS version, Known Issues, and rollback instructions.

## Manual Checks

- Launch signed and notarized app on the release machine.
- Download DMG in a clean environment.
- Verify checksum.
- Drag app to Applications.
- Confirm Gatekeeper does not reject the app.
- Confirm Sparkle local appcast metadata points to the new build.

## Rollback

1. Remove the broken artifact from the release page.
2. Repoint appcast to the previous known-good item or remove the new item.
3. Publish a rollback note explaining the issue and the previous version.
4. Keep the failed notarization and appcast logs for diagnosis.
5. Open a `fix/phase5-release-rollback` branch if code or scripts need changes.

## Known Issues

- Developer ID Application certificate is required for final sign verification.
- Apple notary profile is required for notarization.
- Sparkle update archive signing requires the private EdDSA key in Keychain.
- External MCP, SaaS connectors, full RAG, and Team features are not included in alpha.
