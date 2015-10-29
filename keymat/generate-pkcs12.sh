#!/bin/sh

openssl pkcs12 -export -out $1.pfx -in $1.crt -inkey $1.key
