#!/bin/bash

set -e

if [ "$WITH_PREFERENCES" = "0" ]; then
    # Keep the daemon's existing resource path, without a loadable Settings pane.
    RESOURCE_BUNDLE="$THEOS_STAGING_DIR/Library/PreferenceBundles/TrollVNCPrefs.bundle"
    rm -rf "$RESOURCE_BUNDLE" "$THEOS_STAGING_DIR/Library/PreferenceLoader/Preferences/TrollVNCPrefs"
    mkdir -p "$RESOURCE_BUNDLE"
    cp prefs/TrollVNCPrefs/Resources/Info.plist "$RESOURCE_BUNDLE/Info.plist"
    /usr/libexec/PlistBuddy -c 'Delete :CFBundleExecutable' "$RESOURCE_BUNDLE/Info.plist"
    /usr/libexec/PlistBuddy -c 'Delete :NSPrincipalClass' "$RESOURCE_BUNDLE/Info.plist"
    for LOCALIZATION in prefs/TrollVNCPrefs/Resources/*.lproj; do
        mkdir -p "$RESOURCE_BUNDLE/$(basename "$LOCALIZATION")"
        cp "$LOCALIZATION/Localizable.strings" "$RESOURCE_BUNDLE/$(basename "$LOCALIZATION")/"
    done
    if [ -f prefs/TrollVNCPrefs/Resources/Managed.plist ]; then
        cp prefs/TrollVNCPrefs/Resources/Managed.plist "$RESOURCE_BUNDLE/"
    fi
    # Theos has generated the scheme-specific control file before this hook.
    sed 's/, preferenceloader//' "$THEOS_STAGING_DIR/DEBIAN/control" > "$THEOS_STAGING_DIR/DEBIAN/control.tmp"
    mv "$THEOS_STAGING_DIR/DEBIAN/control.tmp" "$THEOS_STAGING_DIR/DEBIAN/control"
fi

if [ "$THEOS_PACKAGE_SCHEME" = "rootless" ]; then
    /usr/libexec/PlistBuddy -c 'Set :ProgramArguments:0 /var/jb/usr/bin/trollvncserver' "$THEOS_STAGING_DIR/Library/LaunchDaemons/com.82flex.trollvnc.plist"
    /usr/libexec/PlistBuddy -c 'Set :StandardOutPath /var/jb/tmp/trollvnc-stdout.log' "$THEOS_STAGING_DIR/Library/LaunchDaemons/com.82flex.trollvnc.plist"
    /usr/libexec/PlistBuddy -c 'Set :StandardErrorPath /var/jb/tmp/trollvnc-stderr.log' "$THEOS_STAGING_DIR/Library/LaunchDaemons/com.82flex.trollvnc.plist"
fi

if [ -z "$THEBOOTSTRAP" ]; then
    exit 0
fi

# Set version information
GIT_COMMIT_COUNT=$(git rev-list --count HEAD)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $GIT_COMMIT_COUNT" "$THEOS_STAGING_DIR/Applications/TrollVNC.app/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $PACKAGE_VERSION" "$THEOS_STAGING_DIR/Applications/TrollVNC.app/Info.plist"

# Collect executables
cp -rp "$THEOS_STAGING_DIR/usr/bin/trollvncserver" "$THEOS_STAGING_DIR/Applications/TrollVNC.app/"
cp -rp "$THEOS_STAGING_DIR/usr/bin/trollvncmanager" "$THEOS_STAGING_DIR/Applications/TrollVNC.app/"

# Collect bundle resources
cp -rp "$THEOS_STAGING_DIR/Library/PreferenceBundles/TrollVNCPrefs.bundle" "$THEOS_STAGING_DIR/Applications/TrollVNC.app/"
rm -f "$THEOS_STAGING_DIR/Applications/TrollVNC.app/TrollVNCPrefs.bundle/TrollVNCPrefs"
cp -rp "$THEOS_STAGING_DIR/usr/share/trollvnc/webclients" "$THEOS_STAGING_DIR/Applications/TrollVNC.app/"

# Remove unused files
rm -rf "${THEOS_STAGING_DIR:?}/usr"
rm -rf "${THEOS_STAGING_DIR:?}/Library"

# Pseudo code signing
ldid -Sapp/TrollVNC/TrollVNC/TrollVNC.entitlements "$THEOS_STAGING_DIR/Applications/TrollVNC.app"
