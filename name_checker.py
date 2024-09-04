#!/usr/bin/env python3

import subprocess
import argparse
import re

def check_name_uniqueness(name):
    search_commands = [
        f"/TopStor/etcdget.py 10.11.11.100 volumes --prefix",          #should be 10.11.11.100 be dynamic ? 
        f"/TopStor/etcdget.py 10.11.11.100 users --prefix"
    ]

    for command in search_commands:
        try:
            result = subprocess.check_output(command, shell=True, text=True).strip()
            lines = result.splitlines()
            for line in lines:
                match = re.search(r'/([^/]+?)_', line)
                if match:
                    extracted_name = match.group(1)
                    if extracted_name == name:
                        print(f"Invalid: The name '{name}' is already in use.")
                        return 1

        except subprocess.CalledProcessError:
            continue
    
    print(f"Valid: The name '{name}' is available.")
    return 0

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Check the name if unique .")
    parser.add_argument("name", type=str, help="name as input")
    
    args = parser.parse_args()
    
    name_to_check = args.name
    
    exit_code = check_name_uniqueness(name_to_check)
    exit(exit_code)
