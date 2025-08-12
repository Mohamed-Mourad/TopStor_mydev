#!/usr/bin/python3
import socket
import logging

# Setup logger
my_logger = logging.getLogger('my_logger')
my_logger.setLevel(logging.INFO)

handler = logging.FileHandler('mylogfile.log')
formatter = logging.Formatter('%(levelname)s - %(message)s')
handler.setFormatter(formatter)
my_logger.addHandler(handler)

def resolve_domain_server(domsrv):
    try:
        my_logger.info(f"starting resolve for {domsrv} ...")
        addr_info = socket.getaddrinfo(domsrv, None)
        my_logger.info(f"resolve 2, addr_info: {addr_info}")
        
        ipv4_addrs = [ai[4][0] for ai in addr_info if ai[0] == socket.AF_INET]
        my_logger.info(f"resolve 2, ipv4_addrs: {ipv4_addrs}")
        my_logger.info("LOGGING RESOLVE BEFORE IF")
        
        if ipv4_addrs:
            my_logger.info(f"LOGGING RESOLVE IN IF: {ipv4_addrs}")
            return ipv4_addrs[0]
        return None
    except socket.gaierror as e:
        my_logger.info(f"LOGGING RESOLVE IN EXCEPT: {e}")
        return None

# Test with input
if __name__ == "__main__":
    result = resolve_domain_server("cifsd.test")
    print(f"Resolved IP: {result}")

