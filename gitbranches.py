#!/usr/bin/python3
import subprocess
from datetime import datetime

def get_git_branches():
    # Get the list of branches
    branches = subprocess.check_output(['/TopStor/gitbranches.sh']).decode('utf-8').split('\n')
    branches = [branch.strip() for branch in branches if branch.strip()]
    branches = [branch for branch in branches if float(branch.split('QSD')[1].split(',')[0]) > 3.56 ]
    #branches = [{'branch':x.split(',')[0], 'date':x.split(',')[1],'commit':x.split(',')[2]} for x in branches]
    return branches

if __name__ == "__main__":
    branch_info = get_git_branches()
    print(branch_info)
    #for info in branch_info:
    #    print(f"Branch: {info['branch']}")
    #    print(f"Last Commit Date: {info['last_commit_date']}")
    #    print(f"First Commit Hash: {info['first_commit_hash']}")
    #    print("-" * 40)
