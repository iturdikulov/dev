#!/usr/bin/env bash
# Verify Debian ISO authenticity per https://www.debian.org/CD/verify
# 1) OpenPGP signature on SHA256SUMS / SHA512SUMS
# 2) Cryptographic checksum of the ISO against that file
# 3) Optional: check for latest image and offer download

set -euo pipefail

DEBIAN_CD_KEYS=(
    "988021A964E6EA7D"
    "DA87E80D6294BE9B"
    "42468F4009EA8AC3"
)

DEFAULT_MIRROR="https://cdimage.debian.org/debian-cd"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WORKDIR=""
KEEP_WORKDIR=0
ALGO="sha256"
ISO_PATH=""
MIRROR_URL=""
LOCAL_SUMS=""
LOCAL_SIGN=""
ARCH="amd64"
VARIANT="netinst"
OUTPUT_DIR="$SCRIPT_DIR"
AUTO_YES=0
DOWNLOAD_ONLY=0
VERIFY_ONLY=0
SKIP_STARTUP=0
KEYS_PREPARED=0

usage() {
    cat <<'EOF'
Usage: verify-debian-iso.sh [options] [iso-file]

Without iso-file: check latest Debian image, compare with local copies,
offer download and/or verification.

With iso-file: verify GPG signature and checksum of that image.

Options:
  -a, --algo ALGO       sha256 (default) or sha512
  -m, --mirror URL      Mirror URL for checksum files
  --arch ARCH           Architecture (default: amd64)
  --variant VARIANT     Image variant (default: netinst)
  -o, --output DIR      Download directory (default: script directory)
  -y, --yes             Auto-confirm prompts (download/verify)
      --download        Download latest image if needed, then verify
      --verify-only     Only verify, never download
      --skip-startup    Skip latest-version check at startup
  -w, --workdir DIR     Directory for temporary SUMS/key files
  -k, --keep-workdir    Do not delete workdir on exit
      --sums FILE       Use local SHA256SUMS / SHA512SUMS
      --sign FILE       Use local .sign file (required with --sums)
  -h, --help            Show this help

Examples:
  ./verify-debian-iso.sh
  ./verify-debian-iso.sh --download -y
  ./verify-debian-iso.sh debian-13.6.0-amd64-netinst.iso
  ./verify-debian-iso.sh -a sha512 -m https://cdimage.debian.org/debian-cd/current/amd64/iso-cd ./image.iso

Debian CD signing keys:
  https://www.debian.org/CD/verify
EOF
}

log() {
    printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

die() {
    log "ERROR: $*"
    exit 1
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

cleanup() {
    if [[ -n "$WORKDIR" && -d "$WORKDIR" && "$KEEP_WORKDIR" -eq 0 ]]; then
        rm -rf "$WORKDIR"
    fi
}

confirm() {
    local prompt="$1"
    local answer

    if [[ "$AUTO_YES" -eq 1 ]]; then
        return 0
    fi

    if [[ -t 0 ]]; then
        read -r -p "$prompt [Y/n] " answer
    elif read -r answer; then
        :
    else
        die "Non-interactive mode: use -y/--yes to confirm actions"
    fi

    case "${answer:-Y}" in
        Y|y|yes|Yes|YES|"") return 0 ;;
        *) return 1 ;;
    esac
}

download() {
    local url="$1"
    local dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 --retry-delay 2 -o "$dest" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$dest" "$url"
    else
        die "Need curl or wget to download files"
    fi
}

download_resume() {
    local url="$1"
    local dest="$2"
    log "Downloading $(basename "$dest")..."
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 --retry-delay 2 -C - -o "$dest" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -c -O "$dest" "$url"
    else
        die "Need curl or wget to download files"
    fi
}

download_sums_bundle() {
    local mirror="$1"
    local sums="$2"
    local sign="$3"

    download "${mirror}/$(basename "$sums")" "$sums"
    download "${mirror}/$(basename "$sign")" "$sign"
}

current_mirror() {
    echo "${DEFAULT_MIRROR}/current/${ARCH}/iso-cd"
}

ensure_workdir() {
    if [[ -z "$WORKDIR" ]]; then
        WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/debian-iso-verify.XXXXXX")"
        trap cleanup EXIT
    else
        mkdir -p "$WORKDIR"
    fi
}

sums_paths() {
    SUMS_FILE="${WORKDIR}/$(echo "$ALGO" | tr '[:lower:]' '[:upper:]')SUMS"
    SIGN_FILE="${SUMS_FILE}.sign"
    KEYRING="${WORKDIR}/debian-cd-keyring.gpg"
}

import_debian_cd_keys() {
    local keyring="$1"
    local imported=0

    for key_id in "${DEBIAN_CD_KEYS[@]}"; do
        local key_url="https://www.debian.org/CD/key-${key_id}.txt"
        local key_file="${WORKDIR}/debian-cd-key-${key_id}.asc"

        if [[ -f "$key_file" ]]; then
            log "Using cached Debian CD key ${key_id}"
        else
            log "Fetching Debian CD key ${key_id}..."
            if ! download "$key_url" "$key_file"; then
                log "WARNING: failed to download key ${key_id}"
                continue
            fi
        fi

        if gpg --batch --keyring "$keyring" --import "$key_file" >/dev/null 2>&1; then
            imported=1
        fi
    done

    [[ "$imported" -eq 1 ]] || die "Could not import any Debian CD signing keys"
}

verify_gpg_signature() {
    local sums_file="$1"
    local sign_file="$2"
    local keyring="$3"
    local gpg_output

    log "Verifying OpenPGP signature: $(basename "$sign_file")"

    gpg_output="$(
        gpg --batch --status-fd 1 --keyring "$keyring" \
            --verify "$sign_file" "$sums_file" 2>&1
    )" || true

    if grep -q '\[GNUPG:\] VALIDSIG ' <<<"$gpg_output"; then
        local signer
        signer="$(grep '\[GNUPG:\] VALIDSIG ' <<<"$gpg_output" | awk '{print $3}')"
        log "GPG signature is valid (signer key id ends with: ${signer: -8})"
        return 0
    fi

    if grep -q '\[GNUPG:\] GOODSIG ' <<<"$gpg_output"; then
        log "GPG signature is valid"
        return 0
    fi

    log "GPG output:"
    printf '%s\n' "$gpg_output"
    die "GPG signature verification failed"
}

verify_iso_checksum() {
    local iso="$1"
    local sums_file="$2"
    local iso_name expected actual matched_name

    iso_name="$(basename "$iso")"
    expected="$(awk -v iso="$iso_name" '$2 == iso { print $1; exit }' "$sums_file")"

    log "Verifying ${ALGO^^} checksum of $(basename "$iso")..."

    case "$ALGO" in
        sha256) actual="$(sha256sum "$iso" | awk '{print $1}')" ;;
        sha512) actual="$(sha512sum "$iso" | awk '{print $1}')" ;;
        *) die "Unsupported algorithm: $ALGO" ;;
    esac

    if [[ -z "$expected" ]]; then
        matched_name="$(awk -v hash="$actual" '$1 == hash { print $2; exit }' "$sums_file")"
        if [[ -n "$matched_name" ]]; then
            log "Filename not in $(basename "$sums_file"), but hash matches official image: $matched_name"
            expected="$actual"
        else
            die "ISO not found in $(basename "$sums_file"): $iso_name"
        fi
    fi

    if [[ "$actual" == "$expected" ]]; then
        log "Checksum OK (${ALGO})"
        return 0
    fi

    log "Expected: $expected"
    log "Actual:   $actual"
    die "Checksum mismatch"
}

detect_mirror_from_iso() {
    local iso="$1"
    local name version arch variant

    name="$(basename "$iso")"
    if [[ "$name" =~ ^debian-([0-9]+(\.[0-9]+)+)-([a-z0-9_-]+)-([a-z0-9_-]+)\.iso$ ]]; then
        version="${BASH_REMATCH[1]}"
        arch="${BASH_REMATCH[3]}"
        variant="${BASH_REMATCH[4]}"

        case "$variant" in
            netinst|mac|edu) echo "${DEFAULT_MIRROR}/${version}/${arch}/iso-cd" ;;
            *)
                if [[ "$variant" == *dvd* ]]; then
                    echo "${DEFAULT_MIRROR}/${version}/${arch}/iso-dvd"
                else
                    echo "${DEFAULT_MIRROR}/${version}/${arch}/iso-cd"
                fi
                ;;
        esac
        return 0
    fi

    return 1
}

guess_mirror_from_iso() {
    local iso="$1"
    local detected

    if detected="$(detect_mirror_from_iso "$iso")"; then
        echo "$detected"
        return 0
    fi

    current_mirror
}

mirror_candidates() {
    local iso="$1"
    local primary arch detected

    primary="${MIRROR_URL:-$(guess_mirror_from_iso "$iso")}"
    primary="${primary%/}"
    printf '%s\n' "$primary"

    if [[ "$primary" != *"/current/"* ]]; then
        if detected="$(detect_mirror_from_iso "$iso")"; then
            arch="$(basename "$(dirname "$detected")")"
            printf '%s\n' "${DEFAULT_MIRROR}/current/${arch}/iso-cd"
        else
            current_mirror
        fi
    fi
}

fetch_sums_bundle() {
    local iso="$1"
    local sums="$2"
    local sign="$3"
    local mirror

    while IFS= read -r mirror; do
        [[ -n "$mirror" ]] || continue
        log "Trying mirror: $mirror"
        if download_sums_bundle "$mirror" "$sums" "$sign" 2>/dev/null; then
            MIRROR_URL="$mirror"
            return 0
        fi
    done < <(mirror_candidates "$iso")

    die "Could not download checksum files from any mirror. Use --sums/--sign for local files."
}

fetch_current_sums_bundle() {
    local sums="$1"
    local sign="$2"

    MIRROR_URL="$(current_mirror)"
    log "Fetching signed checksums from: $MIRROR_URL"
    download_sums_bundle "$MIRROR_URL" "$sums" "$sign"
}

extract_version() {
    local name="$1"
    if [[ "$name" =~ ^debian-([0-9]+(\.[0-9]+)+)- ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

version_gt() {
    local a="$1"
    local b="$2"
    if [[ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -1)" == "$b" && "$a" != "$b" ]]; then
        return 0
    fi
    return 1
}

iso_name_from_sums_line() {
    awk -v arch="$ARCH" -v variant="$VARIANT" '
        {
            name = $NF
            sub(/^\*/, "", name)
            if (name ~ ("^debian-[0-9]+(\\.[0-9]+)+-" arch "-" variant "\\.iso$")) {
                print name
            }
        }
    ' "$@"
}

find_latest_iso_name() {
    local sums_file="$1"
    iso_name_from_sums_line "$sums_file" | sort -V | tail -1
}

find_local_iso() {
    local dir="$1"
    local pattern="debian-[0-9]*-${ARCH}-${VARIANT}.iso"
    local newest="" newest_ver="" ver f base

    shopt -s nullglob
    for f in "$dir"/$pattern; do
        base="$(basename "$f")"
        [[ "$base" =~ ^debian-[0-9]+(\.[0-9]+)+-${ARCH}-${VARIANT}\.iso$ ]] || continue
        if ver="$(extract_version "$base")"; then
            if [[ -z "$newest_ver" ]] || version_gt "$ver" "$newest_ver"; then
                newest="$f"
                newest_ver="$ver"
            fi
        fi
    done
    shopt -u nullglob

    [[ -n "$newest" ]] && echo "$newest"
}

prepare_keyring() {
    if [[ "$KEYS_PREPARED" -eq 1 ]]; then
        return 0
    fi

    ensure_workdir
    sums_paths
    touch "$KEYRING"
    import_debian_cd_keys "$KEYRING"
    KEYS_PREPARED=1
}

run_verification() {
    local iso="$1"

    [[ -f "$iso" ]] || die "ISO file not found: $iso"
    iso="$(readlink -f "$iso")"

    ensure_workdir
    sums_paths

    log "ISO:    $iso"
    log "Algo:   $ALGO"

    if [[ -n "$LOCAL_SUMS" ]]; then
        cp "$LOCAL_SUMS" "$SUMS_FILE"
        cp "$LOCAL_SIGN" "$SIGN_FILE"
        log "Using local checksum files"
    else
        fetch_sums_bundle "$iso" "$SUMS_FILE" "$SIGN_FILE"
        log "Mirror: $MIRROR_URL"
    fi

    prepare_keyring
    verify_gpg_signature "$SUMS_FILE" "$SIGN_FILE" "$KEYRING"
    verify_iso_checksum "$iso" "$SUMS_FILE"

    log "SUCCESS: image is authentic and checksum matches"
}

download_latest_image() {
    local latest_name dest url

    ensure_workdir
    sums_paths

    fetch_current_sums_bundle "$SUMS_FILE" "$SIGN_FILE"
    prepare_keyring
    verify_gpg_signature "$SUMS_FILE" "$SIGN_FILE" "$KEYRING"

    latest_name="$(find_latest_iso_name "$SUMS_FILE")"
    [[ -n "$latest_name" ]] || die "No image found for ${ARCH}/${VARIANT} in $(basename "$SUMS_FILE")"

    dest="${OUTPUT_DIR%/}/${latest_name}"
    url="${MIRROR_URL}/${latest_name}"

    if [[ -f "$dest" ]]; then
        log "File already exists: $dest"
        if confirm "Re-download and overwrite?"; then
            rm -f "$dest"
        else
            echo "$dest"
            return 0
        fi
    fi

    mkdir -p "$OUTPUT_DIR"
    download_resume "$url" "$dest"
    echo "$dest"
}

print_latest_status() {
    local latest_name="$1"
    local latest_ver="$2"
    local local_iso="$3"

    echo
    log "Latest official image: $latest_name (v${latest_ver})"
    log "Output directory:        $OUTPUT_DIR"

    if [[ -n "$local_iso" ]]; then
        local local_name local_ver
        local_name="$(basename "$local_iso")"
        local_ver="$(extract_version "$local_name")"
        log "Local image:             $local_name (v${local_ver})"

        if [[ "$local_name" == "$latest_name" ]]; then
            log "Local copy matches the latest release."
        elif version_gt "$latest_ver" "$local_ver"; then
            log "Local image is outdated."
        else
            log "Local image version differs from current release."
        fi
    else
        log "Local image:             not found"
    fi
    echo
}

fetch_and_verify_current_sums() {
    ensure_workdir
    sums_paths
    fetch_current_sums_bundle "$SUMS_FILE" "$SIGN_FILE"
    prepare_keyring
    verify_gpg_signature "$SUMS_FILE" "$SIGN_FILE" "$KEYRING"
}

startup_check() {
    local latest_name latest_ver local_iso dest url

    log "Checking latest Debian ${ARCH} ${VARIANT} image..."
    fetch_and_verify_current_sums

    latest_name="$(find_latest_iso_name "$SUMS_FILE")"
    [[ -n "$latest_name" ]] || die "Could not determine latest image name for ${ARCH}/${VARIANT}"
    latest_ver="$(extract_version "$latest_name" || true)"
    [[ -n "$latest_ver" ]] || die "Could not parse version from: $latest_name"
    local_iso="$(find_local_iso "$OUTPUT_DIR" || true)"

    print_latest_status "$latest_name" "$latest_ver" "$local_iso"

    if [[ "$VERIFY_ONLY" -eq 1 ]]; then
        if [[ -n "$local_iso" ]] && confirm "Verify existing local image?"; then
            run_verification "$local_iso"
        fi
        return 0
    fi

    if [[ -n "$local_iso" && "$(basename "$local_iso")" == "$latest_name" ]]; then
        if confirm "Verify local image?"; then
            run_verification "$local_iso"
        fi
        return 0
    fi

    if [[ "$DOWNLOAD_ONLY" -eq 1 ]]; then
        :
    elif ! confirm "Download latest image ($latest_name)?"; then
        if [[ -n "$local_iso" ]] && confirm "Verify existing local image instead?"; then
            run_verification "$local_iso"
        else
            log "Cancelled."
        fi
        return 0
    fi

    dest="${OUTPUT_DIR%/}/${latest_name}"
    url="${MIRROR_URL}/${latest_name}"
    mkdir -p "$OUTPUT_DIR"
    download_resume "$url" "$dest"

    if confirm "Verify downloaded image?"; then
        LOCAL_SUMS=""
        LOCAL_SIGN=""
        run_verification "$dest"
    else
        log "Download complete: $dest"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--algo)
            ALGO="${2:-}"
            shift 2
            ;;
        -m|--mirror)
            MIRROR_URL="${2:-}"
            shift 2
            ;;
        --arch)
            ARCH="${2:-}"
            shift 2
            ;;
        --variant)
            VARIANT="${2:-}"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="${2:-}"
            shift 2
            ;;
        -y|--yes)
            AUTO_YES=1
            shift
            ;;
        --download)
            DOWNLOAD_ONLY=1
            shift
            ;;
        --verify-only)
            VERIFY_ONLY=1
            shift
            ;;
        --skip-startup)
            SKIP_STARTUP=1
            shift
            ;;
        -w|--workdir)
            WORKDIR="${2:-}"
            shift 2
            ;;
        -k|--keep-workdir)
            KEEP_WORKDIR=1
            shift
            ;;
        --sums)
            LOCAL_SUMS="${2:-}"
            shift 2
            ;;
        --sign)
            LOCAL_SIGN="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            die "Unknown option: $1 (use --help)"
            ;;
        *)
            ISO_PATH="$1"
            shift
            ;;
    esac
done

case "$ALGO" in
    sha256|sha512) ;;
    *) die "Unsupported algorithm: $ALGO (use sha256 or sha512)" ;;
esac

need_cmd gpg
need_cmd awk
need_cmd grep
need_cmd sort
if [[ "$ALGO" == sha256 ]]; then
    need_cmd sha256sum
else
    need_cmd sha512sum
fi

OUTPUT_DIR="$(readlink -f "$OUTPUT_DIR")"
MIRROR_URL="${MIRROR_URL%/}"

if [[ -n "$LOCAL_SUMS" || -n "$LOCAL_SIGN" ]]; then
    [[ -n "$LOCAL_SUMS" && -n "$LOCAL_SIGN" ]] || die "Both --sums and --sign are required together"
    [[ -f "$LOCAL_SUMS" ]] || die "SUMS file not found: $LOCAL_SUMS"
    [[ -f "$LOCAL_SIGN" ]] || die "SIGN file not found: $LOCAL_SIGN"
fi

if [[ -n "$ISO_PATH" ]]; then
    if [[ "$SKIP_STARTUP" -eq 0 && -z "$LOCAL_SUMS" ]]; then
        log "Startup check..."
        fetch_and_verify_current_sums
        latest_name="$(find_latest_iso_name "$SUMS_FILE")"
        [[ -n "$latest_name" ]] || die "Could not determine latest image name for ${ARCH}/${VARIANT}"
        latest_ver="$(extract_version "$latest_name" || true)"
        [[ -n "$latest_ver" ]] || die "Could not parse version from: $latest_name"
        local_iso="$(find_local_iso "$OUTPUT_DIR" || true)"
        print_latest_status "$latest_name" "$latest_ver" "$local_iso"
    fi
    run_verification "$ISO_PATH"
    exit 0
fi

startup_check
exit 0
