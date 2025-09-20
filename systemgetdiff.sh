#!/usr/bin/sh
mergedbranch=`git branch | grep '*' | awk '{print $2}'`
echo $mergedbranch | grep _
if [ $? -ne 0 ];
then
	echo Not a merged branch ..it should be having the name RunningBranch_ToTestbranch	
	exit
fi
runbranch=`echo $mergedbranch | awk -F'_' '{print $1}'`
currentbranch='origin/'`echo $mergedbranch | awk -F'_' '{print $2}'`

# TopStor
cd /TopStor/
echo in TopStor
git diff --color=always -U3 $currentbranch $runbranch| less -R

# pace
cd /pace/
echo in pace
git diff --color=always -U3 $currentbranch $runbranch| less -R

# topstorweb
cd /topstorweb/
echo in topstorweb
git diff --color=always -U3 $currentbranch $runbranch| less -R

cd /TopStor
