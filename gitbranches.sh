#!/bin/bash
git for-each-ref --sort=-creatordate --format '%(refname:short) %(creatordate:short) %(objectname:short)' refs/heads/ | while read -r branch date commit; do
	if [[ $branch == QSD* ]];
	then
		number_part=${branch#QSD}

    		# Check if the numeric part is a valid number and greater than 3.50
    		if [[ $number_part =~ ^[0-9]+(\.[0-9]+)?$ ]];
		then
    				echo "$branch, $date, $commit"
		fi
	fi
done
