#!/usr/bin/env bash
# Probe a GitHub-hosted runner: OS, resources, kernel, and tool inventory.
# Designed to run on multiple runner images so we can compare.
#
# Output goes to stdout (visible in the GH Actions UI) AND a probe-RUNNER.json
# file (uploaded as artifact by the parent workflow).

set -euo pipefail

RUNNER="${MATRIX_RUNNER:-unknown}"
SAFE_RUNNER="${RUNNER//\//_}"
STEP_START=$(date +%s.%N)

echo "## runner=$RUNNER"
echo

# ---- OS ----
if [ -f /etc/os-release ]; then
    echo "## os"
    . /etc/os-release 2>/dev/null || true
    printf -- "- id:        %s\n" "${ID:-unknown}"
    printf -- "- name:      %s\n" "${NAME:-unknown}"
    printf -- "- version:   %s\n" "${VERSION_ID:-unknown}"
    printf -- "- codename:  %s\n" "${VERSION_CODENAME:-unknown}"
    echo
fi

# ---- resources ----
echo "## resources"
printf -- "- cpu:        %s\n" "$(nproc 2>/dev/null || echo 1)"
printf -- "- mem_total_mb:%s\n" "$(awk '/^MemTotal:/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo unknown)"
printf -- "- mem_avail_mb:%s\n" "$(awk '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo unknown)"
printf -- "- disk_gb:    %s\n" "$(df -BG / | awk 'NR==2 {gsub("G",""); print $2}')"
printf -- "- tmpfs_gb:   %s\n" "$(df -BG /tmp 2>/dev/null | awk 'NR==2 {gsub("G",""); print $2}')"
echo

# ---- kernel ----
echo "## kernel"
uname -a || true
echo

# ---- tool inventory ----
echo "## tools"
printf "%-14s %s\n" "tool" "version"
printf "%-14s %s\n" "--------------" "----------------------------------------------"
print_tool() {
    local tool="$1"; shift
    local out
    if out=$("$@" 2>&1); then
        out=$(printf '%s' "$out" | head -1)
    else
        out="(not installed)"
    fi
    printf "%-14s %s\n" "$tool" "$out"
}
print_tool bash        bash --version
print_tool git         git --version
print_tool curl        curl --version
print_tool wget        wget --version
print_tool jq          jq --version
print_tool yq          yq --version
print_tool tar         tar --version
print_tool gzip        gzip --version
print_tool ssh         ssh -V
print_tool rsync       rsync --version
print_tool node        node --version
print_tool npm         npm --version
print_tool npx         npx --version
print_tool python3     python3 --version
print_tool pip3        pip3 --version
print_tool go          go version
print_tool java        java -version
print_tool ruby        ruby --version
print_tool perl        perl --version
print_tool gh          gh --version
print_tool docker      docker --version
print_tool buildah     buildah --version
print_tool podman      podman --version
print_tool gcloud      gcloud --version
print_tool az          az --version
print_tool helm        helm version
print_tool kubectl     kubectl version --client
print_tool sqlite3     sqlite3 --version
print_tool psql        psql --version
print_tool redis-cli   redis-cli --version
print_tool shellcheck  shellcheck --version
print_tool shfmt       shfmt --version
print_tool cosign      cosign version
print_tool trivy       trivy --version
echo

# ---- package count (rough indicator of image size) ----
if command -v dpkg >/dev/null 2>&1; then
    echo "## packages"
    printf -- "- dpkg package count: %s\n" "$(dpkg-query -f '${binary:Package}\n' -W 2>/dev/null | wc -l | tr -d ' ')"
    printf -- "- nix:                %s\n" "$(command -v nix || echo NOT_INSTALLED)"
    printf -- "- brew:               %s\n" "$(command -v brew || echo NOT_INSTALLED)"
    echo
fi

# ---- cold-start indicator ----
STEP_END=$(date +%s.%N)
DUR=$(awk "BEGIN {printf \"%.3f\", $STEP_END - $STEP_START}")
echo "## timing (step body only; excludes VM cold-start)"
echo "- step_seconds: $DUR"
echo
echo "(Cold-start = github-billed-minutes minus step time. Measure via"
echo " /repos/.../actions/runs/<id>/timing after the run completes.)"

# ---- machine-readable output ----
{
    printf "{"
    printf '\n  "runner": "%s",'       "$RUNNER"
    printf '\n  "os_id": "%s",'         "${ID:-unknown}"
    printf '\n  "os_name": "%s",'       "${NAME:-unknown}"
    printf '\n  "os_version": "%s",'    "${VERSION_ID:-unknown}"
    printf '\n  "cpu": %s,'             "$(nproc 2>/dev/null || echo 1)"
    printf '\n  "mem_total_mb": %s,'    "$(awk '/^MemTotal:/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
    printf '\n  "disk_gb": %s,'         "$(df -BG / | awk 'NR==2 {gsub("G",""); print $2}')"
    printf '\n  "step_seconds": %s'    "$DUR"
    printf "\n}\n"
} > "probe-${SAFE_RUNNER}.json"

echo
echo "----- artifact file -----"
ls -la "probe-${SAFE_RUNNER}.json"
