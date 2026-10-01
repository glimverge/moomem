#!/usr/bin/env bash
# Bump moon.mod version by BUMP (major|minor|patch|alpha|beta).
# Writes base_version / mod_version / prerelease to GITHUB_OUTPUT when set.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MOD_FILE="${ROOT}/moon.mod"
BUMP="${BUMP:?BUMP is required (major|minor|patch|alpha|beta)}"

parse_version() {
  local v="$1"
  if [[ "${v}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-(alpha|beta)\.([0-9]+))?$ ]]; then
    MAJOR="${BASH_REMATCH[1]}"
    MINOR="${BASH_REMATCH[2]}"
    PATCH="${BASH_REMATCH[3]}"
    PRE_KIND="${BASH_REMATCH[5]:-}"
    PRE_NUM="${BASH_REMATCH[6]:-0}"
  else
    echo "Unsupported version format: ${v} (want X.Y.Z or X.Y.Z-alpha.N / X.Y.Z-beta.N)" >&2
    exit 1
  fi
}

bump_version() {
  local kind="$1"
  case "${kind}" in
    major)
      echo "$((MAJOR + 1)).0.0"
      ;;
    minor)
      echo "${MAJOR}.$((MINOR + 1)).0"
      ;;
    patch)
      echo "${MAJOR}.${MINOR}.$((PATCH + 1))"
      ;;
    alpha)
      if [[ "${PRE_KIND}" == "alpha" ]]; then
        echo "${MAJOR}.${MINOR}.${PATCH}-alpha.$((PRE_NUM + 1))"
      elif [[ "${PRE_KIND}" == "beta" ]]; then
        echo "${MAJOR}.${MINOR}.${PATCH}-alpha.1"
      else
        echo "${MAJOR}.${MINOR}.$((PATCH + 1))-alpha.1"
      fi
      ;;
    beta)
      if [[ "${PRE_KIND}" == "beta" ]]; then
        echo "${MAJOR}.${MINOR}.${PATCH}-beta.$((PRE_NUM + 1))"
      elif [[ "${PRE_KIND}" == "alpha" ]]; then
        echo "${MAJOR}.${MINOR}.${PATCH}-beta.1"
      else
        echo "${MAJOR}.${MINOR}.$((PATCH + 1))-beta.1"
      fi
      ;;
    *)
      echo "Unknown bump type: ${kind}" >&2
      exit 1
      ;;
  esac
}

base_version="$(sed -nE 's/^version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "${MOD_FILE}" | head -n1)"
if [[ -z "${base_version}" ]]; then
  echo "Could not parse version from moon.mod" >&2
  exit 1
fi
parse_version "${base_version}"

new_version="$(bump_version "${BUMP}")"
is_prerelease=false
if [[ "${new_version}" == *"-alpha."* || "${new_version}" == *"-beta."* ]]; then
  is_prerelease=true
fi

tmp="$(mktemp)"
sed -E "s/^version[[:space:]]*=[[:space:]]*\"[^\"]+\"/version = \"${new_version}\"/" "${MOD_FILE}" > "${tmp}"
mv "${tmp}" "${MOD_FILE}"

echo "Bump ${BUMP}: ${base_version} → ${new_version}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "base_version=${base_version}"
    echo "mod_version=${new_version}"
    echo "prerelease=${is_prerelease}"
  } >> "${GITHUB_OUTPUT}"
fi
