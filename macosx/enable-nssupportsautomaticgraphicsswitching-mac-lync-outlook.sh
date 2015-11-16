#!/bin/bash

# For more information, please refer to
# http://answers.microsoft.com/en-us/mac/forum/macoffice2011-macoutlook/office-for-mac-mavericks-high-performance-gpu/e1a6aff0-e36e-40ae-ab62-aa7e3e0c6b10.

# Enable for Lync
AppName="/Applications/Microsoft Lync.app"
defaults write "$AppName/Contents/Info.plist" "NSSupportsAutomaticGraphicsSwitching" -bool true
if [ $? -eq 0 ]; then
   chmod 664 "$AppName/Contents/Info.plist"
   # Code sign Lync again
   codesign -f --verbose --deep -s - "$AppName/"
fi

# Enable for Outlook
AppName="/Applications/Microsoft Office 2011/Microsoft Outlook.app"
defaults write "$AppName/Contents/Info.plist" "NSSupportsAutomaticGraphicsSwitching" -bool true
if [ $? -eq 0 ]; then
   # Code sign Lync again
   chmod 664 "$AppName/Contents/Info.plist"
   codesign -f --verbose --deep -s - "$AppName/"
fi
