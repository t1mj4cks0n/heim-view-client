#!/usr/bin/python3
import os
import json
import time
import logging
import subprocess
import urllib.request
from urllib.request import urlopen
from collections import ChainMap
import datetime
import hashlib

# --- Constants ---
current_path = os.path.dirname(os.path.abspath(__file__))
BASE_DIR = current_path
CONFIG_FILE = os.path.join(BASE_DIR, "data", "config.json")
LOG_FILE = os.path.join(BASE_DIR, "data", "logs", "client.log")
UPDATE_LOG_FILE = os.path.join(BASE_DIR, "data", "logs", "update.log")
CACHE_DIR = os.path.join(BASE_DIR, "data", "cache")
CACHE_FILE = os.path.join(CACHE_DIR, "public_ip_cache.json")
                          
GITHUB_REPO = "https://raw.githubusercontent.com/t1mj4cks0n/heim-view-client/main"

# --- Default Config ---
DEFAULT_CONFIG = {
    "server_url": "http://127.0.0.1:5000/log",
    "interval_seconds": 30,
    "auto_update": False,
    "github_repo": GITHUB_REPO,
    "version": "1.0",
    "update_check_interval": 3600  # 1 hour
}

# --- Setup ---
os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
os.makedirs(os.path.dirname(UPDATE_LOG_FILE), exist_ok=True)
os.makedirs(CACHE_DIR, exist_ok=True)
logging.basicConfig(filename=LOG_FILE, level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")

# --- Helper Functions ---
def load_config():
    try:
        if os.path.exists(CONFIG_FILE):
            with open(CONFIG_FILE, "r") as f:
                user_config = json.load(f)
        else:
            user_config = {}
        config = DEFAULT_CONFIG.copy()
        for key, value in user_config.items():
            config[key] = value
        return config
    except Exception as e:
        logging.error(f"Error loading config: {e}")
        return DEFAULT_CONFIG

def ensure_cache_exists():
    """Ensure cache directory/file exist."""
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        if not os.path.exists(CACHE_FILE):
            with open(CACHE_FILE, 'w') as f:
                json.dump({'ip': None, 'timestamp': 0}, f)
    except IOError as e:
        logging.error(f"Error creating cache: {e}")

# --- Stat Collection Functions ---
def get_hostname():
    """Get system hostname."""
    try:
        return {'hostname': os.uname().nodename}
    except Exception as e:
        logging.error(f"Error getting hostname: {e}")
        return {'hostname': str(e)}

def get_cpu_usage(interval=1):
    """Get CPU usage per core and total."""
    def get_cpu_times():
        with open('/proc/stat', 'r') as f:
            lines = f.readlines()
        cpu_times = {}
        for line in lines:
            if line.startswith('cpu'):
                parts = line.split()
                core = parts[0]
                times = list(map(int, parts[1:]))
                cpu_times[core] = times
        return cpu_times
    try:
        times1 = get_cpu_times()
        time.sleep(interval)
        times2 = get_cpu_times()
        cores = [core for core in times1.keys() if core.startswith('cpu') and core != 'cpu']
        num_cores = len(cores)
        result = {'num_cores': num_cores}
        total_usage = 0
        for i, core in enumerate(cores):
            delta = [t2 - t1 for t1, t2 in zip(times1[core], times2[core])]
            idle_time = delta[3]
            total_time = sum(delta)
            core_usage = 100.0 * (1.0 - idle_time / total_time)
            result[f'core_{i+1}'] = round(core_usage, 2)
            total_usage += core_usage
        result['total_usage'] = round(total_usage / num_cores, 2) if num_cores > 0 else 0
        return result
    except Exception as e:
        logging.error(f"Error getting CPU usage: {e}")
        return {'error': str(e)}

def get_memory_usage():
    """Get memory usage stats."""
    try:
        mem_info = {}
        with open('/proc/meminfo', 'r') as f:
            for line in f:
                if line.startswith('MemTotal'):
                    mem_info['total'] = int(line.split()[1])
                elif line.startswith('MemFree'):
                    mem_info['free'] = int(line.split()[1])
                elif line.startswith('Buffers'):
                    mem_info['buffers'] = int(line.split()[1])
                elif line.startswith('Cached'):
                    mem_info['cached'] = int(line.split()[1])
        used = mem_info['total'] - mem_info['free'] - mem_info['buffers'] - mem_info['cached']
        mem_info['used'] = used
        mem_info['total_mb'] = round(mem_info['total'] / 1024, 2)
        mem_info['used_mb'] = round(used / 1024, 2)
        mem_info['free_mb'] = round(mem_info['free'] / 1024, 2)
        mem_info['percent_used'] = round((used / mem_info['total']) * 100, 2)
        return {
            'total_mem_mb': mem_info['total_mb'],
            'used_mem_mb': mem_info['used_mb'],
            'free_mem_mb': mem_info['free_mb'],
            'percent_mem_used': mem_info['percent_used']
        }
    except Exception as e:
        logging.error(f"Error getting memory usage: {e}")
        return {'error': str(e)}

def get_storage_stats():
    """Get root (/) storage stats."""
    try:
        storage_stats = {}
        result = subprocess.run(['df', '-m'], capture_output=True, text=True)
        lines = result.stdout.splitlines()
        for line in lines:
            parts = line.split()
            if len(parts) >= 6 and parts[5] == '/':
                storage_stats['storage_used'] = int(parts[2])
                storage_stats['storage_max'] = int(parts[1])
                break
        return storage_stats
    except Exception as e:
        logging.error(f"Error getting storage stats: {e}")
        return {'error': str(e)}

def get_boot_time():
    """Get system boot time."""
    try:
        with open('/proc/uptime', 'r') as f:
            uptime_seconds = float(f.readline().split()[0])
        boot_time = datetime.datetime.fromtimestamp(time.time() - uptime_seconds)
        return {'boot_time': boot_time.strftime('%Y-%m-%d %H:%M:%S')}
    except Exception as e:
        logging.error(f"Error getting boot time: {e}")
        return {'error': str(e)}

def get_outdated_packages():
    """Get list of upgradable packages."""
    try:
        result = subprocess.run(['apt', 'list', '--upgradable'], capture_output=True, text=True)
        outdated_packages = [line.split('/')[0] for line in result.stdout.splitlines() if '/' in line]
        return {'outdated_packages': outdated_packages}
    except Exception as e:
        logging.error(f"Error getting outdated packages: {e}")
        return {'error': str(e)}

def get_network_interfaces():
    """Get network interfaces (excluding lo/docker)."""
    try:
        result = subprocess.run(['ip', 'addr'], capture_output=True, text=True)
        interfaces = []
        current_interface = None
        for line in result.stdout.splitlines():
            line = line.strip()
            if line and line[0].isdigit() and ':' in line:
                interface_name = line.split(':')[1].strip().split('@')[0]
                if interface_name in ('lo', 'docker0'):
                    current_interface = None
                else:
                    current_interface = interface_name
                    interfaces.append({'int_face_name': current_interface, 'int_face_mac': None, 'int_face_ip': None})
            elif current_interface and 'link/ether' in line:
                mac = line.split('link/ether')[1].split()[0].strip()
                for iface in interfaces:
                    if iface['int_face_name'] == current_interface:
                        iface['int_face_mac'] = mac
                        break
            elif current_interface and 'inet ' in line and 'scope global' in line:
                ip = line.split('inet ')[1].split('/')[0].strip()
                for iface in interfaces:
                    if iface['int_face_name'] == current_interface:
                        iface['int_face_ip'] = ip
                        break
        return {'interfaces': interfaces}
    except Exception as e:
        logging.error(f"Error getting network interfaces: {e}")
        return {'error': str(e)}

def get_public_ip():
    """Get public IP (cached for 1 hour)."""
    try:
        cached_ip, last_update_time = load_cache()
        current_time = time.time()
        if not cached_ip or (current_time - last_update_time) >= 3600:
            with urlopen('https://api.ipify.org?format=json', timeout=5) as response:
                data = json.loads(response.read().decode())
                cached_ip = data['ip']
                save_cache(cached_ip, current_time)
        return {'public_ip': cached_ip}
    except Exception as e:
        logging.error(f"Error fetching public IP: {e}")
        return {'public_ip': cached_ip}

def load_cache():
    """Load cached IP and timestamp."""
    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, 'r') as f:
                cache = json.load(f)
                return cache.get('ip'), cache.get('timestamp', 0)
        except (json.JSONDecodeError, IOError) as e:
            logging.error(f"Error loading cache: {e}")
    return None, 0

def save_cache(ip, timestamp):
    """Save cached IP and timestamp."""
    try:
        with open(CACHE_FILE, 'w') as f:
            json.dump({'ip': ip, 'timestamp': timestamp}, f)
    except IOError as e:
        logging.error(f"Error saving cache: {e}")

def send_to_server(data, server_url):
    """Send stats to the Heim-View Server using urllib."""
    try:
        data["client_version"] = DEFAULT_CONFIG["version"]
        req = urllib.request.Request(
            server_url,
            data=json.dumps(data).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST"
        )
        with urllib.request.urlopen(req, timeout=10) as response:
            return response.status == 200
    except Exception as e:
        logging.error(f"Failed to send data: {e}")
        return False

def get_stats():
    """Collect all stats."""
    try:
        return ChainMap(
            get_outdated_packages(),
            get_storage_stats(),
            get_cpu_usage(),
            get_memory_usage(),
            get_public_ip(),
            get_network_interfaces(),
            get_boot_time(),
            get_hostname()
        )
    except Exception as e:
        logging.error(f"Error collecting stats: {e}")
        return {'error': str(e)}

# --- Main Loop ---
if __name__ == "__main__":
    config = load_config()
    ensure_cache_exists()
    logging.info(f"Starting heim-view v{config.get('version', '1.0')}")
    while True:
        stats = dict(get_stats())
        success = send_to_server(stats, config["server_url"])
        if not success:
            logging.warning("Failed to send data. Retrying next interval.")
        time.sleep(config["interval_seconds"])
