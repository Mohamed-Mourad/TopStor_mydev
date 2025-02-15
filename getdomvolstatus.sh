#!/bin/sh
export ETCDCTL_API=3
cd /TopStor/
volip=`echo $@ | awk '{print $1}'`
vtype=`echo $@ | awk '{print $2}'`
voldocker=`docker ps | grep $volip | awk '{print $NF}'`
echo s$voldocker | grep $vtype >/dev/null
if [ $? -ne 0 ];
then
	echo _resultservicedown_result
	exit
fi
dockerlogs=`docker logs $voldocker 2>&1`
echo NFS | grep $vtype
if [ $? -eq 0 ];
then
	echo $dockerlogs | grep 'Startup successful'
	if [ $? -eq 0 ];
	then
		echo _resultserviceok_result
		exit
	else
		echo _resultservicedown_result
		exit
	fi
fi
	
dockerlogs=`docker logs $voldocker 2>&1`
echo $dockerlogs | grep skew >/dev/nul
if [ $? -eq 0 ];
then
	echo _resulttimeerror_result
	exit
fi
echo $dockerlogs | grep 'Preauthentication failed' >/dev/null
if [ $? -eq 0 ];
then
	echo _resultadminpasserror_result
	exit
fi
echo $dockerlogs | grep 'NT_STATUS_NO_LOGON_SERVERS'  >/dev/null
if [ $? -eq 0 ];
then
	echo $dockerlogs | grep 'Successfully discovered' >/dev/null
	if [ $? -eq 0 ];
	then
		echo _resultADnameerror_result
		exit
	else
		echo _resultADservererror_result
		exit
	fi
fi

echo $dockerlogs | grep 'Cannot contact any KDC for realm' >/dev/null
if [ $? -eq 0 ];
then
	echo _resultADservererror_result
	exit
fi
echo $dockerlogs | grep "realm: Couldn't join realm: Operation was cancelled" >/dev/null
if [ $? -eq 0 ];
then
	echo _resultADservererror_result
	exit
fi
echo $dockerlogs | grep 'Realm not local to KDC ' >/dev/null
if [ $? -eq 0 ];
then
	echo _resultADservererror_result
	exit
fi
echo $dockerlogs | grep 'sssd is running' >/dev/null
if [ $? -eq 0 ];
then
	echo _resultserviceok_result
	#echo _resultunknownerror_result
else
	echo $dockerlogs | grep 'sssd is not running'
	if [ $? -eq 0 ];
	then
		echo _resultADservererror_result
	else
		echo _resultService is loading _result
	fi
fi
