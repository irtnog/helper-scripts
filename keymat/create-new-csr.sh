#!/bin/sh

openssl req -outform PEM -out $1.csr -new -subj /O=IRTNOG/OU=IT/CN=$1/emailAddress=security@irtnnog.org/L=Masson/ST=Ohio/C=US -newkey rsa:4096 -keyout $1.key -nodes -sha512 -batch && cat $1.csr
