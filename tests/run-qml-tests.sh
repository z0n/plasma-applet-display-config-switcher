#!/bin/sh
set -eu

# Invoke with sh; the optional first argument selects the Qt 6 test runner.
runner=${1:-/usr/lib/qt6/bin/qmltestrunner}
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/display-profiles-test.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
mkdir -p "$scratch/config" "$scratch/bin"
cat > "$scratch/bin/kscreen-doctor" <<'EOF'
#!/bin/sh
if [ "$#" -eq 1 ] && [ "$1" = "-j" ]; then
    printf '%s\n' '{"outputs":[{"name":"TEST-1","enabled":true}]}'
else
    exit 1
fi
EOF
chmod +x "$scratch/bin/kscreen-doctor"
XDG_CONFIG_HOME="$scratch/config" PATH="$scratch/bin:$PATH" \
    QT_QPA_PLATFORM=offscreen "$runner" -file-selector isolated-profile-tests -input "$root/tests/qml"
