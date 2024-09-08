#!/usr/bin/env python3

import subprocess
import argparse
import re

def run_command(vtype):
    command = f"/TopStor/etcdget.py 10.11.11.100 volumes --prefix | grep {vtype.upper()}"
    try:
        result = subprocess.check_output(command, shell=True, text=True)
        print("Command Output:")
        print(result)
        return result
    except subprocess.CalledProcessError as e:
        print(f"An error occurred while running the command: {e}")
        return None

def getClusterIp():
    output = subprocess.check_output("/TopStor/etcdget.py 10.11.11.100 clusternodeip --prefix", shell=True, text=True)
    pattern = r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}'
    match = re.search(pattern, output)
    if match:
        clusterIp = match.group()
        return clusterIp
    else:
        raise ValueError("No IP address found in output")

def check_ip_uniqueness(ip, vtype):
    command = f"/TopStor/etcdget.py 10.11.11.100 volumes --prefix | grep {ip}"

    try:
        result = subprocess.check_output(command, shell=True, text=True)
        result = result.strip()

        if vtype.upper() in result:
            print("Invalid IP")
            return 1
        
        print("Valid IP")
        return 0

    except subprocess.CalledProcessError:
        print("Valid IP")
        return 0

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Check if an IP is valid and does not conflict with existing IPs.")
    parser.add_argument("ip", type=str, help="The IP address to check.")
    parser.add_argument("vtype", type=str.upper, choices=['CIFS', 'HOME', 'NFS', 'ISCSI'], help="The type of the IP address (CIFS or NFS).")

    args = parser.parse_args()

    ip_to_check = args.ip
    vtype = args.vtype

    exit_code = check_ip_uniqueness(ip_to_check, vtype)
    exit(exit_code)
