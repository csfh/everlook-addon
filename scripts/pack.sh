#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
core="${root}/Everlook"
version="${1:-}"
outdir="${2:-$root/dist}"

if [[ -z "${version}" ]]; then
  version="$(awk -F': ' '/^## Version:/{gsub("\r","",$2); print $2; exit}' "${core}/Everlook.toc")"
fi

if [[ -z "${version}" ]]; then
  echo "Could not determine Everlook version from Everlook/Everlook.toc" >&2
  exit 1
fi

stage="$(mktemp -d)"
trap 'rm -rf "${stage}"' EXIT
mkdir -p "${outdir}"

folders=()
for source in "${root}"/Everlook "${root}"/Everlook_*; do
  [[ -d "${source}" ]] || continue
  name="$(basename "${source}")"
  folders+=("${name}")
  while IFS= read -r -d '' file; do
    rel="${file#./}"
    dest="${stage}/${name}/${rel}"
    mkdir -p "$(dirname "${dest}")"
    cp -a "${source}/${rel}" "${dest}"
  done < <(
    cd "${source}"
    find . -type f \
      ! -path './sign.lua' \
      ! -path './sign_template.lua' \
      \( -name '*.lua' -o -name '*.toc' -o -name '*.xml' -o -name '*.tga' -o -name '*.ttf' -o -name '*.txt' \) \
      -print0
  )
done

# Releases always carry the clean stub, never the developer's local token.
cp "${core}/sign_template.lua" "${stage}/Everlook/sign.lua"

# The MIT license has to travel with every copy of the code.
if [[ ! -f "${root}/LICENSE" ]]; then
  echo "Missing LICENSE; the archive must carry it" >&2
  exit 1
fi
cp "${root}/LICENSE" "${stage}/Everlook/LICENSE"

# Module TOCs carry no version in the repository. Each release stamps the
# core's version into them so the addon list shows one version for the set.
for name in "${folders[@]}"; do
  [[ "${name}" == Everlook ]] && continue
  toc="${stage}/${name}/${name}.toc"
  awk -v version="${version}" '{ print } /^## Interface:/ { print "## Version: " version }' "${toc}" > "${toc}.stamped"
  mv "${toc}.stamped" "${toc}"
done

archive="${outdir}/Everlook-${version}.tar.gz"
tar -C "${stage}" -czf "${archive}" "${folders[@]}"
cp "${archive}" "${outdir}/Everlook-latest.tar.gz"

interface="$(awk -F': ' '/^## Interface:/{gsub("\r","",$2); print $2; exit}' "${core}/Everlook.toc")"
title="$(awk -F': ' '/^## Title:/{gsub("\r","",$2); print $2; exit}' "${core}/Everlook.toc")"
uv run --no-project python - "${outdir}/Everlook.json" "${title:-Everlook}" "${version}" "${interface}" <<'PY'
import json
import sys

path, title, version, interface = sys.argv[1:5]
with open(path, "w", encoding="utf-8") as handle:
    json.dump({"title": title, "version": version, "interface": interface or None}, handle)
    handle.write("\n")
PY

members="$(tar -tzf "${archive}")"
for name in "${folders[@]}"; do
  if ! grep -Fx "${name}/${name}.toc" <<<"${members}" >/dev/null; then
    echo "Packed archive is missing ${name}/${name}.toc" >&2
    exit 1
  fi
done

echo "${archive}"
