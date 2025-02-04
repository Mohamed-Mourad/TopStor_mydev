#!/usr/bin/python3
import subprocess
from datetime import datetime

def get_git_branches():
    # Get the list of branches
    branches = subprocess.check_output(['git', 'branch']).decode('utf-8').split('\n')
    branches = [branch.strip() for branch in branches if branch.strip()]
    return branches

def get_last_commit_date(branch):
    # Get the last commit date for the branch
    date_str = subprocess.check_output(['git', 'log', '-1', '--format=%cd', branch]).decode('utf-8').strip()
    date_format = "%a %b %d %H:%M:%S %Y %z"
    date_obj = datetime.strptime(date_str, date_format)
    smalldate = date_obj.strftime("%Y-%m-%d")
    return smalldate 

def get_first_commit_hash(branch):
    # Get the first commit hash (first 5 characters) for the branch
    hash_str = subprocess.check_output(['git', 'rev-list', '--max-parents=0', branch]).decode('utf-8').strip()
    return hash_str[:7]

def get_branch_info():
    branches = get_git_branches()
    branch_info = []
    for branch in branches:
        try:
            last_commit_date = get_last_commit_date(branch)
            first_commit_hash = get_first_commit_hash(branch)
            branch_info.append({
                'branch': branch,
                'last_commit_date': last_commit_date,
                'first_commit_hash': first_commit_hash
            })
        except:
            continue
    print(branch_info)
    return branch_info

if __name__ == "__main__":
    branch_info = get_branch_info()
    print(branch_info)
    #for info in branch_info:
    #    print(f"Branch: {info['branch']}")
    #    print(f"Last Commit Date: {info['last_commit_date']}")
    #    print(f"First Commit Hash: {info['first_commit_hash']}")
    #    print("-" * 40)
