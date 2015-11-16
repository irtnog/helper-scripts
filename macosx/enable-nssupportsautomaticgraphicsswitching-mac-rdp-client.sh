#!/bin/bash

# For more information, please refer to
# http://answers.microsoft.com/en-us/mac/forum/macoffice2011-macoutlook/office-for-mac-mavericks-high-performance-gpu/e1a6aff0-e36e-40ae-ab62-aa7e3e0c6b10.

AppName="/Applications/Microsoft Remote Desktop.app"
defaults write "$AppName/Contents/Info.plist" "NSSupportsAutomaticGraphicsSwitching" -bool true
if [ $? -eq 0 ]; then
   chmod 664 "$AppName/Contents/Info.plist"
   codesign -f --verbose --deep -s - "$AppName/"
fi
