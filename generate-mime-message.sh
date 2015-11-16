#!/bin/bash

## http://backreference.org/2013/05/22/send-email-with-attachments-from-script-or-command-line/

get_mimetype(){
  # warning: assumes that the passed file exists
  file --mime-type "$1" | sed 's/.*: //' 
}

from="$1"
to="$2"
subject="$3"
boundary="ZZ_/afg6432dfgkl.94531q"
body="$4"
file="$5"

{

printf '%s\n' "From: $from
To: $to
Subject: $subject
Mime-Version: 1.0
Content-Type: multipart/mixed; boundary=\"$boundary\"

--${boundary}
Content-Type: text/plain; charset=\"US-ASCII\"
Content-Transfer-Encoding: 7bit
Content-Disposition: inline

$body
"

[ ! -f "$file" ] && echo "Warning: attachment $file not found, skipping" >&2 && continue
mimetype=$(get_mimetype "$file")
filename=$(basename "$file")
printf '%s\n' "--${boundary}
Content-Type: $mimetype
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename=\"$filename\"
"
base64 -b 70 "$file"
echo
 
# print last boundary with closing --
printf '%s\n' "--${boundary}--"
 
}
