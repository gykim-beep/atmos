#!/bin/sh
xattr -cr "$TARGET_BUILD_DIR" || true
xattr -cr "$CODESIGNING_FOLDER_PATH" || true
