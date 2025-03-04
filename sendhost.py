#!/usr/bin/python3
import pika
from ast import literal_eval as mtuple

def sendhost(host, req, que, frmhst, port=5672):
 with open('/root/sendhostparam','a') as f:
  f.write(host+' '+str(req)+' '+str(que)+' '+str(frmhst)+'\n')
# Check if the file needs to be pruned
 with open('/root/sendhostparam', 'r') as f:
        lines = f.readlines()

 if len(lines) > 30:
        # Keep only the last 30 lines
        with open('/root/sendhostparam', 'w') as f:
            f.writelines(lines[-30:])
# creds=pika.PlainCredentials('rabb_'+frmhst,'YousefNadody')
 creds=pika.PlainCredentials('rabb_Mezo','YousefNadody')
 param=pika.ConnectionParameters(host, port, '/', creds)
 conn=pika.BlockingConnection(param)
 chann=conn.channel()
 chann.basic_publish(exchange='',routing_key=que, body=str(req))
 conn.close()
if __name__ == "__main__":
 import sys
 sendhost(*sys.argv[1:])
 
