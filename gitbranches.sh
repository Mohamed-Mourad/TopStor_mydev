#!/bin/sh
git for-each-ref --sort=-creatordate --format '%(refname:short) %(creatordate:short) %(objectname:short)' refs/heads/ | while read -r branch date commit; do
    echo "$branch,$date,$commit"
done
