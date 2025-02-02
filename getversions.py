#!/usr/bin/python3

import subprocess, os

def getversions():
 current_directory = os.getcwd()
 print("Current Working Directory:", current_directory)
 new_directory = "/TopStor" 
 os.chdir(new_directory)
 cmdline='git branch'
 cversion= "" 
 versions = []
 verdict = dict()
 result=subprocess.run(cmdline.split(),stdout=subprocess.PIPE).stdout
 os.chdir(current_directory)
 id = 0
 for res in result.decode('utf-8').split('\n'):
  if 'QS' in res:
   if '*' in res:
    cversion = res.split(' ')[1]
    print(cversion)
   versions.append({'id': id, 'text':res.split('QSD')[1]})
   id += 1
 verdict = { 'versions': versions, 'current': cversion } 
 return verdict 

if __name__=='__main__':
 getversions()
