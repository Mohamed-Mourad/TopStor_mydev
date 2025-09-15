#!/usr/bin/python3
import sys, subprocess
from putzpool import putzpool, initputzpool
from allphysicalinfo import getall 
from etcdget import etcdget as get
from getallraids import newraids, initgetraids
from fastselect import selectdisks
from levelthis import levelthis
from time import sleep
allinfo = {}

def dgsnewpool(data):
 global allinfo, leader, leaderip, clusterip, myhost, myhostip
 keys = []
 dgsinfo = {'raids':allinfo['raids'], 'pools':allinfo['pools'], 'disks':allinfo['disks']}
 dgsinfo['newraid'] = newraids(allinfo['disks'])
 if data['useable'] not in dgsinfo['newraid'][data['redundancy']]:
  keys = list(dgsinfo['newraid'][data['redundancy']].keys())
  keys.append(float(data['useable']))
  keys.sort()
  diskindx = keys.index(float(data['useable'])) + 1
  if diskindx == len(keys):
   diskindx = len(keys) - 2 
  data['useable'] = keys[diskindx]
 disks =  dgsinfo['newraid'][data['redundancy']][data['useable']]
 if 'single' in data['redundancy']:
  selecteddisks= disks
 else:
  print('selectdisks',disks, allinfo['disks'])
  bestdisks = selectdisks(leaderip, disks, allinfo['disks'])
 if len(bestdisks) < 1:
    return jsonify(data)
 selecteddisks = bestdisks.split(',')
 diskstring = ''
 for dsk in selecteddisks:
  diskstring += dsk+":"+dsk[-5:]+" "
 print('#############################3')
 print(';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;')
 print(selecteddisks)
 print('#########################333')
 owner = myhost 
 data['user'] = 'system'
 if 'single' in data['redundancy']:
  datastr = 'Single '+data['user']+' '+owner+" "+selecteddisks[0]+" "+selecteddisks[0][-5:]+" nopool "+data['user']+" "+owner
 elif 'mirror' in data['redundancy']:
  datastr = 'mirror '+data['user']+' '+owner+" "+diskstring+"nopool "+data['user']+" "+owner
 elif 'volset' in data['redundancy']:
  datastr = 'stripeset '+data['user']+' '+owner+" "+diskstring+" "+data['user']+" "+owner
 elif 'raid5' in data['redundancy']:
  datastr = 'parity '+data['user']+' '+owner+" "+diskstring
 elif 'raid6plus' in data['redundancy']:
  datastr = 'parity3 '+data['user']+' '+owner+" "+diskstring+" "+data['user']+" "+owner
 elif 'raid6' in data['redundancy']:
  datastr = 'parity2 '+data['user']+' '+owner+" "+diskstring+" "+data['user']+" "+owner
 cmndstring = '/TopStor/DGsetPool '+leaderip+' '+datastr+' '+data['user']
 print('creating pool')
 print(cmndstring)
 subprocess.run(cmndstring.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
 print('pool is created')
 putzpool()
 alldsks = get(leaderip,'host','current')
 allinfo = getall(leaderip, alldsks)
 newpool = allinfo['disks'][selecteddisks[0]]['pool']
 createdpool = newpool
 host = allinfo['pools'][createdpool]['host']
 hostip = allinfo['hosts'][host]['ipaddress']
 result = hostip+':'+createdpool+'/'
 return result

def selectDG(volsize):
 global allinfo, leader, leaderip, clusterip, myhost, myhostip
 posraids = newraids(allinfo['disks'])
 raidname = 'noraid'
 raidsize = float('inf')
 data = { 'useable': volsize, 'redundancy':'noraid' }
 createdpool = 'nopool'
 for raid in posraids:
  if ('mirror' or 'raid') in raid: 
   for raidsz in posraids[raid]:
    if raidsz > data['useable']:
     data['useable'] = raidsz 
     data['redundancy'] = raid
 if  'noraid' in data['redundancy']:
  return 'No_vol_space'
 return dgsnewpool(data) 
  
 
  
def selectPool(volsize):
 global leader, leaderip, clusterip, myhost, myhostip
 pools = allinfo['pools']
 volquota = levelthis(volsize,'G')
 pool = 'No_vol_space'
 poolsize = float('inf')
 host = 'No_vol_space'
 for pol in pools:
  if 'pree' not in pol and 'Availability' in pools[pol]['availtype'] and levelthis(pools[pol]['available']) > volquota and pools[pol]['available'] < poolsize:
   pool = pol
   poolsize = pools[pol]['available']
   host = allinfo['hosts'][pools[pol]['host']]['ipaddress']
 pools = host+':'+pool+'/'
 return pools 
   
 
def selectVol(volname, volsize):
 global leader, leaderip, clusterip, myhost, myhostip
 volinfo = allinfo['volumes']
 volumes='No_vol_space'
 for vol in volinfo:
  volshort='_'.join(vol.split('_')[:-1])
  if volshort == volname:
   if levelthis(volinfo[vol]['available']) > levelthis(volsize) - levelthis(volinfo[vol]['used']):
    hostip = allinfo['hosts'][volinfo[vol]['host']]['ipaddress']
    csnaps = 'csnaps,'+','.join(allinfo['volumes'][vol]['snapshots'])
    volumes = hostip+':'+volinfo[vol]['pool']+'/'+vol+'@'+csnaps
   else:
    volumes='No_vol_space'
 return volumes



if __name__=='__main__':
 with open('/root/repliSelection','w') as f:
  f.write(str(sys.argv))
 volname = sys.argv[1]
 volsize = float(sys.argv[2])
 snapshot = sys.argv[3]
 cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py leader'
 leader=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
 cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py leaderip'
 leaderip=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
 cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py clusternode'
 myhost=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
 cmdline='docker exec etcdclient /TopStor/etcdgetlocal.py clusternodeip'
 myhostip=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').replace('\n','').replace(' ','')
 initgetraids(leader, leaderip, myhost, myhostip)
 initputzpool(leader, leaderip, myhost, myhostip)
 
 #snapused = levelthis(sys.argv[4])
 alldsks = get(leaderip, 'host','current')
 allinfo = getall(leaderip, alldsks)
 #volsize = sys.argvlevelthis('96K','G')
 #snapused = levelthis('1K','G')
 #volname = 'common_427522895'
 print('check existing volumes.....')
 replivol= selectVol(volname,volsize)
 if 'No_vol_space' in replivol:
  print('continuing to check existing pool.....')
  replivol = selectPool(volsize)+volname
  if 'No_vol_space' in replivol:
   print('continuing to create a pool....')
   replivol = selectDG(volsize)+volname
 print('result_'+replivol+'result_')

   
  
# disks = allinfo['disks']
# raids = newraids(disks)
# print(raids)
 
