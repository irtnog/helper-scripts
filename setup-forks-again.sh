#!/bin/sh

while read dir repo upstream
do
    git clone git@github.com:$repo
    cd $dir
    BRANCH=`git branch | awk '{print $2}'`
    git remote add upstream git@github.com:$upstream
    git fetch upstream
    git merge --ff-only upstream/$BRANCH
    git push
    cd ..
done < forks
