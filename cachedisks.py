#!/usr/bin/env python3
import sys
import json
import subprocess
from etcdget import etcdget as get
from etcdput import etcdput as put


def _normalize_current_json(current_json):
    if not current_json or current_json == 'None':
        return []

    val = current_json
    
    if isinstance(val, tuple) and len(val) > 1:
        val = val[1]

    for _ in range(3):
        try:
            parsed = json.loads(val)
        except (TypeError, ValueError):
            break
        else:
            val = parsed
            if isinstance(val, list):
                return [str(x) for x in val]

    if isinstance(val, list):
        return [str(x) for x in val]

    return [str(val)] if val else []


def main():
    if len(sys.argv) < 3:
        sys.exit(1)

    action = sys.argv[1]
    leader_ip = sys.argv[2]
    disks_arg = sys.argv[3:]
    etcd_key = "cachespares"

    res = get(leader_ip, etcd_key, "--prefix")
    
    current_json = None
    if isinstance(res, tuple) and len(res) >= 2:
        current_json = res[1]
    elif isinstance(res, list) and len(res) > 0 and isinstance(res[0], tuple):
        current_json = res[0][1]
    else:
        current_json = res

    try:
        current_list = _normalize_current_json(current_json)
    except Exception:
        current_list = []

    new_list = list(current_list)

    if action == "del":
        if not disks_arg:
            new_list = []
        else:
            new_list = [d for d in current_list if d not in disks_arg]
    elif action == "add":
        for d in disks_arg:
            d = str(d)
            if d not in new_list:
                new_list.append(d)

    if set(new_list) != set(current_list):
        put(leader_ip, etcd_key, json.dumps(new_list))
        subprocess.run(["/pace/putzpool.py"])


if __name__ == "__main__":
    main()
