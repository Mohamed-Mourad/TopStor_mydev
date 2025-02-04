#!/usr/bin/python3

import subprocess, os
from ast import literal_eval as mtuple

def getversions():
 current_directory = os.getcwd()
 new_directory = "/TopStor" 
 os.chdir(new_directory)
 cmdline='git status'
 cversion= "" 
 versions = []
 verdict = dict()
 result=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8')
 cmdline = '/TopStor/gitbranches.sh'
 allbranches=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout.decode('utf-8').split('\n')
 os.chdir(current_directory)
 id = 0
 cversion = result.split('\n')[0].split('branch ')[1]
 id = 1 
 for version in allbranches:
   versions.append({'id': id, 'text':version})
   id += 1
 verdict = { 'versions': versions, 'current': cversion } 
 print(verdict)
 return verdict 

if __name__=='__main__':
 getversions()
