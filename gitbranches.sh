#!/usr/bin/sh
for branch in $(git for-each-ref --format='%(refname:short)' refs/heads/); do
  echo "$(git log -1 --format='%ci' $branch) $branch"
done | sort | awk '{print $1" "$4}'
