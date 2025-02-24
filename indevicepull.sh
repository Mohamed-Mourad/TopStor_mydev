#!/usr/bin/sh
fnupdate () {
	rm -rf pre_apply.sh	
	echo '###########################################' $1
	git fetch indevice $1
	if [ $? -ne 0 ];
	then
		echo something went wrong while updating $1 .... consult the devleloper
		exit
	fi
	git branch -D tempb
	git checkout -- *
	git rm -rf __py*
	rm -rf __py*
	git checkout -b tempb
	git branch -D $1
	git checkout -b $1 indevice/$1
	git reset --hard
	git checkout -- *
	git rm -rf __py*
	rm -rf __py*
	sync
	sync
	sync
}
cjobs=(`echo TopStor pace topstorweb`)
cd /TopStor.bak/TopStor
branch=`git for-each-ref --sort=-committerdate refs/heads/ --format='%(refname:short)' --count=1`
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
		git remote -v | grep indevice
		bakpath='/'${job}'.bak/'$job
		echo git remote add indevice $bakpath 
		git remote add indevice $bakpath 
		fnupdate $branch 
		cjobs=(`echo "${cjobs[@]}" | sed "s/$job//g" `)
  	done
	lencjobs=`echo $cjobs | wc -c`
	if [ $lencjobs -le 3 ];
	then
		flag=0
	fi
done
echo running any needed scripts
/TopStor/pre_apply.sh	
cd /topstorweb
git show | grep commit
cd /pace
git show | grep commit
cd /TopStor
git show | grep commit
echo finished
