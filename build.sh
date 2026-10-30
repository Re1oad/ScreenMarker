#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP=build/ScreenMarker.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 -o "$APP/Contents/MacOS/ScreenMarker" Sources/main.swift
cp Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
echo "Built $APP"
