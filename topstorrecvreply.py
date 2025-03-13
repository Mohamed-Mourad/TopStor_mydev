#!/usr/bin/python3
import pika, sys, subprocess
import actionreply


def callback(ch, method, properties, body):
 global leader, leaderip, myhost, myip, etcdip
 #with open('/root/toactionreply','w') as f:
 #f.write(" ".join([leader, leaderip, myhost, myip,etcdip, str(body)]))
 print(" ".join([leader, leaderip, myhost, myip,etcdip, str(body)]))
 with open("/root/recvreply",'a') as f:
    f.write(" ".join([leader, leaderip, myhost, myip,etcdip, str(body)]))
    
 actionreply.do(leader, leaderip, myhost, myip,etcdip, body.decode())

cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py leader'
leader=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py leaderip'
leaderip=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py clusternode'
myhost=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py clusternodeip'
myip=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
if leader == myhost:
    etcdip = leaderip
else:
    etcdip = myip
print('myip',myip)
cred = pika.PlainCredentials('rabb_Mezo', 'YousefNadody')
param = pika.ConnectionParameters(myip,5672, '/', cred)
conn = pika.BlockingConnection(param)
chann= conn.channel()
chann.queue_declare(queue='recvreply')
#chann.basic_consume(callback, queue='recvreply', no_ack=True)
chann.basic_consume('recvreply',callback, True)
chann.start_consuming()
