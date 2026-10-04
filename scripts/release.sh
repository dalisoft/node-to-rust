#!/usr/bin/env bash
# Publish validated formats; unchanged source/toolchain inputs exit successfully.
set -euo pipefail
cd "$(dirname "$0")/.."
temp_dir=$(mktemp -d)
trap 'rm -r "$temp_dir"' EXIT
assets=(from-javascript-to-rust.epub from-javascript-to-rust.azw3)
git ls-files -z book scripts .github/workflows/ebooks.yml Gemfile Gemfile.lock \
  .ruby-version from-javascript-to-rust.epub > "$temp_dir/inputs"
fingerprint=$(
  while IFS= read -r -d '' name; do
    printf '%s\0' "$name"; cat "$name"; printf '\0'
  done < "$temp_dir/inputs" | shasum -a 256 | cut -d ' ' -f1
)
case "${1:-}" in
  check)
    changed=true
    tag=$(gh release list --limit 1 --json tagName --jq '.[0].tagName // empty')
    if [ -n "$tag" ]; then
      gh release view "$tag" --json assets > "$temp_dir/release.json"
      if jq -e --arg epub "${assets[0]}" --arg azw3 "${assets[1]}" \
        '[.assets[].name] | contains([$epub, $azw3, "build-manifest.json"])' "$temp_dir/release.json" >/dev/null; then
        gh release download "$tag" --pattern build-manifest.json --dir "$temp_dir"
        if [ "$(jq -er .source_sha256 "$temp_dir/build-manifest.json")" = "$fingerprint" ]; then changed=false; fi
      fi
    fi
    printf 'changed=%s\n' "$changed"
    if [ -n "${GITHUB_OUTPUT:-}" ]; then printf 'changed=%s\n' "$changed" >> "$GITHUB_OUTPUT"; fi
    ;;
  publish)
    for name in "${assets[@]}"; do test "$(wc -c < "output/$name")" -gt 1000; done
    commit=$(git rev-parse HEAD)
    jq -n --arg source "$fingerprint" --arg commit "$commit" \
      --arg epub "${assets[0]}" --arg azw3 "${assets[1]}" \
      --arg epub_hash "$(shasum -a 256 "output/${assets[0]}" | cut -d ' ' -f1)" \
      --arg azw3_hash "$(shasum -a 256 "output/${assets[1]}" | cut -d ' ' -f1)" \
      '{source_sha256:$source, commit:$commit, assets:{($epub):$epub_hash, ($azw3):$azw3_hash}}' > output/build-manifest.json
    today=$(TZ=Asia/Samarkand date +%F)
    tag="release-$today"
    gh release list --limit 100 --json tagName > "$temp_dir/releases.json"
    if jq -e --arg tag "$tag" 'any(.[]; .tagName == $tag)' "$temp_dir/releases.json" >/dev/null; then
      gh release upload "$tag" "output/${assets[0]}" "output/${assets[1]}" output/build-manifest.json --clobber
    else
      gh release create "$tag" "output/${assets[0]}" "output/${assets[1]}" output/build-manifest.json \
        --target "$commit" --title "From JavaScript to Rust — $today" \
        --notes 'Repaired EPUB and Kindle-compatible AZW3, built from the original AsciiDoc sources. Includes packaged images, repaired internal references, code highlighting, and author metadata. Book license: CC BY-NC 4.0. build-manifest.json records source and asset SHA-256 hashes.'
    fi
    gh release view "$tag" --json url
    ;;
  *) echo 'Usage: bash scripts/release.sh check|publish' >&2; exit 2 ;;
esac
