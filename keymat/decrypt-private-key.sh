#!/bin/sh

openssl rsa -in $1.key.enc -out $1.key
