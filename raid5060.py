#!/usr/bin/python3
"""
RAID 50/60 configuration and disk selection helpers.

RAID50 = striped RAIDZ1 groups (fixed width 3 disks per vdev in this flow).
RAID60 = striped RAIDZ2 groups (fixed width 4 disks per vdev in this flow).

Both configurations require at least 2 parity vdev groups:
 - RAID50 minimum disks: 6 (2 x 3)
 - RAID60 minimum disks: 8 (2 x 4)

Selection is delegated to fastselect.selectdisks so host balancing uses the
same weighted logic used by other RAID paths.
"""

from fastselect import selectdisks


def _get_striped_parity(single, diskdict, vdev_width, parity):
 """Build striped parity options in the common raid output format."""
 theraid = dict()
 min_groups = 2
 min_disks = vdev_width * min_groups

 for size in single:
  otherslist = []
  hosts = set()
  othershosts = set()
  posdiskc = 0

  for others in single:
   if others > size:
    posdiskc += len(single[others])
    otherslist.append(others)
    for dsk in single[others]:
     othershosts.add(diskdict[dsk]['host'])

  for dsk in single[size]:
   hosts.add(diskdict[dsk]['host'])

  total = posdiskc + len(single[size])
  if total < min_disks:
   continue

  max_groups = total // vdev_width
  groups = min_groups
  while groups <= max_groups:
   diskcount = groups * vdev_width
   useable = round(size * (vdev_width - parity) * groups, 2)
   theraid[useable] = {
    'disk': size,
    'diskcount': diskcount,
    'others': otherslist,
    'hosts': list(hosts),
    'othershosts': list(othershosts),
   }
   groups += 1

 return theraid


def getraid50(single, diskdict):
 """Compute available RAID50 configurations from free disk groups."""
 return _get_striped_parity(single, diskdict, vdev_width=3, parity=1)


def getraid60(single, diskdict):
 """Compute available RAID60 configurations from free disk groups."""
 return _get_striped_parity(single, diskdict, vdev_width=4, parity=2)


def _select_raidx0(leaderip, fdisks, fdisksinfo, vdev_width, addtopool='', excludelst=''):
 """Validate group sizing then use fastselect balancing to pick disks."""
 diskcount = fdisks.get('diskcount', 0)
 min_disks = vdev_width * 2
 if diskcount < min_disks or diskcount % vdev_width != 0:
  return ''
 return selectdisks(leaderip, fdisks, fdisksinfo, addtopool, excludelst)


def selectraid50(leaderip, fdisks, fdisksinfo, addtopool='', excludelst=''):
 """Select RAID50 disks using the same balancing engine as other RAIDs."""
 return _select_raidx0(leaderip, fdisks, fdisksinfo, vdev_width=3, addtopool=addtopool, excludelst=excludelst)


def selectraid60(leaderip, fdisks, fdisksinfo, addtopool='', excludelst=''):
 """Select RAID60 disks using the same balancing engine as other RAIDs."""
 return _select_raidx0(leaderip, fdisks, fdisksinfo, vdev_width=4, addtopool=addtopool, excludelst=excludelst)

