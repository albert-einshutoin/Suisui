# Distribution Packaging

SoloPM public alpha の標準配布物は `DMG` とする。Mac ユーザーが Finder 上で `SoloPM.app` を `Applications` に移せるように、DMG には `/Applications` への symlink を含める。

Sparkle appcast 用、または notarization submission 用には ZIP も生成できるが、ユーザー向けの標準 download は DMG に寄せる。

## Build Package

署名済み、notarized、staple 済みの `dist/SoloPM.app` を作った後に実行する。

```bash
./script/package_release.sh
```

出力先は `dist/releases/`。

```text
SoloPM-0.1.0+1.dmg
SoloPM-0.1.0+1.dmg.sha256
```

ZIP も同時に作る場合は次を使う。

```bash
SOLOPM_PACKAGE_FORMAT=all ./script/package_release.sh
```

署名環境がない開発機で packaging smoke だけ確認する場合は、明示的に署名要求を外す。

```bash
SOLOPM_REQUIRE_SIGNED_PACKAGE=0 \
SOLOPM_REQUIRE_NOTARIZED_PACKAGE=0 \
./script/package_release.sh
```

release artifact を作る通常実行では、`SOLOPM_REQUIRE_SIGNED_PACKAGE=1` と `SOLOPM_REQUIRE_NOTARIZED_PACKAGE=1` が既定値になる。つまり `codesign --verify`、`xcrun stapler validate`、`spctl -a -vv` を通らない app bundle からは配布用 DMG / ZIP を作らない。

## Checksum

各 artifact には `shasum -a 256` の checksum を出す。GitHub Release や release notes には artifact 名と checksum を併記する。

## Manual Check

clean 環境で以下を確認する。

1. DMG を download する。
2. checksum が release notes と一致する。
3. DMG を開き、`SoloPM.app` と `Applications` symlink が見える。
4. `SoloPM.app` を Applications に移動する。
5. 初回起動時に Gatekeeper で拒否されない。
