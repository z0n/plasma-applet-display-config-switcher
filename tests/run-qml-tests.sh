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
    printf '%s\n' '{"outputs":[{"name":"TEST-1","connected":true,"enabled":true,"scale":1,"rotation":16,"overscan":0,"currentModeId":"live","modes":[{"id":"live","name":"1920x1080@60","refreshRate":60,"size":{"width":1920,"height":1080}}]}]}'
elif [ "$*" = "output.TEST-1.enable output.TEST-1.mode.live output.TEST-1.scale.1 output.TEST-1.rotation.flipped output.TEST-1.overscan.0" ]; then
    exit 0
else
    exit 1
fi
EOF
chmod +x "$scratch/bin/kscreen-doctor"
XDG_CONFIG_HOME="$scratch/config" PATH="$scratch/bin:$PATH" \
    QT_QPA_PLATFORM=offscreen "$runner" -file-selector isolated-profile-tests -input "$root/tests/qml"
