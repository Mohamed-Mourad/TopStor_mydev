#!/usr/bin/env python3
import sys
import subprocess
import time
import os

PROM_FILE = "/TopStordata/prom_metrics/zfs_custom.prom"
HEARTBEAT_FILE = "/tmp/ui_active_heartbeat"

def get_pool_metrics():
    try:
        output = subprocess.check_output(['zpool', 'iostat', '-lp']).decode('utf-8')
        lines = output.splitlines()
        
        metrics = [
            "# HELP zfs_pool_read_iops Total read IOPS per pool",
            "# TYPE zfs_pool_read_iops gauge",
            "# HELP zfs_pool_write_iops Total write IOPS per pool",
            "# TYPE zfs_pool_write_iops gauge",
            "# HELP zfs_pool_read_latency_ns Read latency in nanoseconds",
            "# TYPE zfs_pool_read_latency_ns gauge",
            "# HELP zfs_pool_write_latency_ns Write latency in nanoseconds",
            "# TYPE zfs_pool_write_latency_ns gauge"
        ]
        
        for line in lines[3:]:
            parts = line.split()
            if len(parts) < 7 or parts[0].startswith('-'):
                continue
                
            pool_name = parts[0]
            metrics.append(f'zfs_pool_read_iops{{pool="{pool_name}"}} {parts[3]}')
            metrics.append(f'zfs_pool_write_iops{{pool="{pool_name}"}} {parts[4]}')
            metrics.append(f'zfs_pool_read_latency_ns{{pool="{pool_name}"}} {parts[7] if len(parts) > 7 else "0"}')
            metrics.append(f'zfs_pool_write_latency_ns{{pool="{pool_name}"}} {parts[8] if len(parts) > 8 else "0"}')

        # Atomic write to prevent prometheus reading a half-written file
        with open(PROM_FILE + '.tmp', 'w') as f:
            f.write('\n'.join(metrics) + '\n')
        subprocess.call(['mv', PROM_FILE + '.tmp', PROM_FILE])
        
    except Exception as e:
        print(f"Failed to scrape ZFS: {e}")

def get_last_heartbeat():
    try:
        if os.path.exists(HEARTBEAT_FILE):
            with open(HEARTBEAT_FILE, 'r') as f:
                return int(f.read().strip())
    except Exception:
        pass
    return 0

def run_daemon():
    print("Leader node confirmed. Starting smart telemetry daemon...")
    while True:
        last_ping = get_last_heartbeat()
        current_time = time.time()

        if current_time - last_ping < 5:
            # BOOST MODE (UI is open)
            get_pool_metrics()
            time.sleep(0.25)
            
        else:
            # IDLE MODE (UI is closed)
            get_pool_metrics()
            
            # Interruptible Sleep (10s total, checks every 0.25s)
            for _ in range(40): 
                time.sleep(0.25)
                if time.time() - get_last_heartbeat() < 5:
                    print("UI connection detected! Waking up...")
                    break 

if __name__ == "__main__":
    # 1. HA Logic: Extract IP arguments passed by the bash looper
    if len(sys.argv) < 3:
        print("Missing leaderip and myhost arguments. Exiting.")
        sys.exit(1)
        
    leaderip = sys.argv[1]
    myhost = sys.argv[2]
    
    # 2. HA Logic: If I am a Follower node, exit immediately.
    # The bash looper will catch this exit, sleep for 5s, and loop again.
    if leaderip != myhost:
        print(f"Follower node ({myhost} != {leaderip}). Exiting.")
        sys.exit(0)
        
    # 3. If I am the Leader, run forever.
    run_daemon()
