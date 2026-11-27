#!/bin/bash
set -e
cd "$(dirname "$0")"
APP=build/Uphora.app
rm -rf build
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
swiftc -O -module-name Uphora -o $APP/Contents/MacOS/Uphora Sources/*.swift
cp icon/AppIcon.icns $APP/Contents/Resources/AppIcon.icns
cp Info.plist $APP/Contents/Info.plist
codesign --force --sign - $APP
echo "Built $APP"
