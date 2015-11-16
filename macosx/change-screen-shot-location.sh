#!/bin/sh

if [ "$1" != "" ]; then
  [ ! -d "$1" ] && mkdir -p "$1"
  ABSPATH="`perl -MCwd -e 'print Cwd::abs_path("'"$1"'");'`"
  defaults write com.apple.screencapture location "${ABSPATH}"
  killall SystemUIServer
fi

defaults read com.apple.screencapture location
