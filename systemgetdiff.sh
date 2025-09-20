#!/usr/bin/sh
currentbranch=`git branch | grep '*' | awk '{print $2}'`
echo $currentbranch | grep _
if [ $? -ne 0 ];
then
	echo Not a merged branch ..it should be having the name RunningBranch_ToTestbranch	
	exit
fi
runbranch=`echo $currentbranch | awk -F'_' '{print $1}'`

#!/bin/bash

# TopStor
cd /TopStor/
git diff --color=always -U3 $runbranch..$currentbranch | less -R

# pace
cd /pace/
git diff --color=always -U3 $runbranch..$currentbranch | less -R

# topstorweb
cd /topstorweb/
git diff --color=always -U3 $runbranch..$currentbranch | less -R

cd /TopStor
