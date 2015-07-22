#!/bin/sh

echo `basename $1` >> forks
git clone git@github.com:$1
cd `basename $1`
BRANCH=`git branch | awk '{print $2}'`
git remote add upstream git@github.com:$2
git fetch upstream
git merge --ff-only upstream/$BRANCH
git push
