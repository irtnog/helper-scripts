#!/bin/sh

cd $1
BRANCH=`git branch | grep '^\*' | awk '{print $2}'`
git fetch upstream
git merge --ff-only upstream/$BRANCH
git push
cd ..
