#!/bin/sh
set -eu

case "$CONFIGURATION" in
  Debug) cli_configuration=debug ;;
  *) cli_configuration=release ;;
esac
cli_scratch="$DERIVED_FILE_DIR/ViewinCLI"
# Forward architectures so universal app archives also contain a universal CLI.
set --
for cli_arch in $ARCHS; do set -- "$@" --arch "$cli_arch"; done
/usr/bin/xcrun swift build --package-path "$SRCROOT/Core" --scratch-path "$cli_scratch" \
  --configuration "$cli_configuration" --product viewin "$@"
cli_bin=$(/usr/bin/xcrun swift build --package-path "$SRCROOT/Core" --scratch-path "$cli_scratch" \
  --configuration "$cli_configuration" --show-bin-path "$@")
helper_dir="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
mkdir -p "$helper_dir"
/usr/bin/install -m 755 "$cli_bin/viewin" "$helper_dir/viewin"
# SwiftPM resource lookup for a standalone executable uses its adjacent bundle.
/usr/bin/ditto "$cli_bin/ViewinCore_ViewinSnapshot.bundle" "$helper_dir/ViewinCore_ViewinSnapshot.bundle"
if [ "${CODE_SIGNING_ALLOWED:-NO}" = YES ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
  /usr/bin/codesign --force --options runtime --timestamp \
    --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$helper_dir/viewin"
fi
