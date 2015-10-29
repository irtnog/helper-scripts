#!/bin/sh

openssl req -outform PEM -out $1.crt -x509 -subj /O=IRTNOG/OU=IT/CN=$1/emailAddress=security@irtnog.org/L=Mason/ST=Ohio/C=US -newkey rsa:4096 -keyout $1.key -nodes -sha512 -days 365 -batch
