#!/usr/bin/sh
fnupdate () {
	echo '###########################################' $1
	git branch | grep $1
	if [ $? -ne 0 ];
	then
		echo something went wrong while updating $1, no such branch .... consult the devleloper
		exit
	fi
	git checkout -- *
	git rm -rf __py*
	rm -rf __py*
	git checkout $1 
	sync
	sync
	sync
}
cjobs=(`echo TopStor pace topstorweb`)
echo $@ > /root/changeversion
branch=$1
branchc=`echo $branch | wc -c`
if [ $branchc -le 3 ];
then
	echo no valid branch is supplied .... exiting
	exit
fi 
echo $branch | grep samebranch
if [ $? -eq 0 ];
then
	branch=`git branch | grep '*' | awk '{print $2}'`
fi
flag=1
while [ $flag -ne 0 ];
do
	rjobs=(`echo "${cjobs[@]}"`)
	echo rjobs=${rjobs[@]}
	for job in "${rjobs[@]}";
	do
 		echo $job
		cd /$job
		if [ $? -ne 0 ];
		then
			echo the directory $job is not found... exiting
			exit
		fi
		fnupdate $branch 
		cjobs=(`echo "${cjobs[@]}" | sed "s/$job//g" `)
  	done
	lencjobs=`echo $cjobs | wc -c`
	if [ $lencjobs -le 3 ];
	then
		flag=0
	fi
done
cd /Test_topstorweb
git show | grep commit
cd /Test_pace
git show | grep commit
cd /Test_TopStor
git show | grep commit
cd /TopStor
echo finished
