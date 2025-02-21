#!/usr/bin/python3
import sys, subprocess, datetime
from logqueue import queuethis, initqueue
from etcdgetpy import etcdget as get
from sendhost import sendhost


def create(leader, leaderip, myhost, myhostip, etcdip, pool, name, ipaddr, ipsubnet, vtype,*args):
    volsip = get(etcdip,'volume','/'+ipaddr+'/')
    volsip = [ x for x in volsip if 'active' in str(x) ]
    nodesip = get(etcdip, 'Active','/'+ipaddr+'/') 
    notsametype = [ x for x in volsip if vtype not in str(x) ]
    if (len(nodesip) > 0 and 'Active' in str(nodesip))or len(notsametype) > 0:
        print('ipaddr',ipaddr)
        print('nodesip',len(nodesip), nodesip)
        print('nodtsametype',len(notsametype), notsametype)
        print(' the ip address is in use ')
        return
    resname = vtype+'-'+ipaddr
    cmdline='rm -rf /TopStordata/tempnfs.'+ipaddr
    subprocess.run(cmdline.split(),stdout=subprocess.PIPE)  
    mounts =''
    writes =''
    for vol in volsip:
        if vol in notsametype:
           continue
        leftvol = vol[0].split('/')[4]
        mounts += '-v/'+pool+'/'+leftvol+':/'+pool+'/'+leftvol+':rw'
        rightvol = vol[1].split('/_u_')[1].split('/')[0]
        rightvolu = rightvol.split('_u_')[0]
        rightvolg = rightvol.split('_u_')[1]
        writes += '_vol_/'+pool+'/'+leftvol+'_u_'+rightvolu+'_u_'+rightvolg
   #     with open('/TopStordata/tempnfs.'+ipaddr,'a') as fip:
   #         try:
   #             with open('/'+pool+'/exports.'+leftvol, 'r') as fvol:
   #                 fip.write(fvol.read())
   #         except:
   #            continue 
    if len(volsip) < 1 :
        return
    #who = volsip[0][1].split('/')[2]
    #exports = ''
    #for vol in volsip:
    #    if vol in notsametype:
    #       continue
    #    exp = '/'+vol[0].split('/')[3]+'/'+vol[0].split('/')[4]
    #    exports = exp +' '+ who+'('+','.join(vol[1].split('/')[3:8])+')\n'
    #    with open('/TopStordata/exportip.'+vol[0].split('/')[4]+'_'+ipaddr,'w') as fip:
    #        fip.write(exports)
     
    cmdline = '/TopStor/nfsnew.sh 'leaderip+' '+resname+' '+mounts+' '+ipaddr+' '+ipsubnet+' '+vtype+' '+'/'+pool+'/'+leftvol+' '+writes+'_vol_'

    print('second cmdline',cmdline)
    subprocess.run(cmdline.split(),stdout=subprocess.PIPE)  
    return
    #if len(checkipaddr1) != 0 or len :

 

if __name__=='__main__':
 leader = sys.argv[1]
 leaderip = sys.argv[2]
 myhost = sys.argv[3]
 myhostip = sys.argv[4]
 etcdip = sys.argv[5]
 pool = sys.argv[6]
 name = sys.argv[7]
 ipaddr = sys.argv[8]
 ipsubnet = sys.argv[9]
 vtype = sys.argv[10]
 initqueue(leaderip, myhost)
 with open('/root/nfsnewpytmp','w') as f:
  f.write(str(sys.argv))
 create(leader, leaderip, myhost, myhostip, etcdip, pool, name, ipaddr, ipsubnet, vtype,*sys.argv[11:])
