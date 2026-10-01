"""Read-only Linux sampler. Standard library only; streams one JSON object per sample."""
import argparse
import json
import math
import os
import pwd
import re
import signal
import socket
import subprocess
import time
import xml.etree.ElementTree as ET


def number(text):
    if text is None:
        return None
    match = re.match(r"^\s*(-?\d+(?:\.\d+)?)", str(text))
    if not match:
        return None
    value = float(match.group(1))
    return value if math.isfinite(value) and value >= 0 else None


def cpu_counters(text):
    values = [int(x) for x in text.splitlines()[0].split()[1:9]]
    # guest time is already included in user/nice, so do not count it twice.
    return sum(values), values[3] + (values[4] if len(values) > 4 else 0)


def cpu_usage(previous, current):
    if previous is None:
        return None
    total, idle = current[0] - previous[0], current[1] - previous[1]
    return max(0.0, min(100.0, 100.0 * (total - idle) / total)) if total > 0 else None


def memory_values(text):
    fields = {}
    for line in text.splitlines():
        key, value = line.split(":", 1)
        fields[key] = int(value.split()[0]) / 1024.0
    total = fields.get("MemTotal", 0)
    available = fields.get("MemAvailable", fields.get("MemFree", 0) + fields.get("Buffers", 0) + fields.get("Cached", 0) + fields.get("SReclaimable", 0) - fields.get("Shmem", 0))
    return max(0, total - available), total


def parse_process_stat(text):
    # comm can contain spaces and parentheses; fields after its closing paren are stable.
    fields = text[text.rfind(")") + 2:].split()
    return int(fields[11]) + int(fields[12]), fields[19]


class Sampler:
    def __init__(self):
        self.previous_cpu = None
        self.previous_processes = {}
        self.ticks = os.sysconf("SC_CLK_TCK")

    def process_details(self, pid, now, current):
        details = {"user": "—", "command": "", "cpuPercent": None}
        try:
            folder = "/proc/" + str(pid)
            details["user"] = pwd.getpwuid(os.stat(folder).st_uid).pw_name
            with open(folder + "/cmdline", "rb") as file:
                details["command"] = file.read(16384).replace(b"\0", b" ").decode("utf-8", "replace").strip()
            with open(folder + "/stat") as file:
                ticks, started = parse_process_stat(file.read())
            current[pid] = (ticks, now, started)
            prior = self.previous_processes.get(pid)
            if prior and prior[2] == started and now > prior[1]:
                # top-style process CPU: one fully occupied core is 100%.
                details["cpuPercent"] = max(0, (ticks - prior[0]) / self.ticks / (now - prior[1]) * 100)
        except (OSError, ValueError, KeyError, IndexError):
            pass  # The process may exit, or /proc may restrict access.
        return details

    def parse_gpus(self, xml, now):
        root = ET.fromstring(xml)
        gpus, processes, current = [], [], {}
        for index, gpu in enumerate(root.findall("gpu")):
            uuid = gpu.findtext("uuid") or gpu.get("id") or str(index)
            gpus.append({
                "index": index, "uuid": uuid, "name": gpu.findtext("product_name") or "NVIDIA GPU",
                "utilization": number(gpu.findtext("utilization/gpu_util")),
                "memoryUsed": number(gpu.findtext("fb_memory_usage/used")),
                "memoryTotal": number(gpu.findtext("fb_memory_usage/total")),
                "temperature": number(gpu.findtext("temperature/gpu_temp")),
                "powerDraw": number(gpu.findtext("gpu_power_readings/power_draw") or gpu.findtext("power_readings/power_draw")),
                "powerLimit": number(gpu.findtext("gpu_power_readings/power_limit") or gpu.findtext("power_readings/power_limit")),
            })
            seen = set()
            for proc in gpu.findall("processes/process_info"):
                pid_text = proc.findtext("pid")
                if not pid_text or not pid_text.isdigit():
                    continue
                pid = int(pid_text)
                if pid in seen:
                    continue
                seen.add(pid)
                details = self.process_details(pid, now, current)
                processes.append({
                    "gpuUUID": uuid, "gpuIndex": index, "pid": pid,
                    "name": proc.findtext("process_name") or "unknown",
                    "type": proc.findtext("type") or "—",
                    "memoryUsed": number(proc.findtext("used_memory")), **details,
                })
        self.previous_processes = current
        return gpus, processes

    def sample(self):
        warnings = []
        with open("/proc/stat") as file:
            current_cpu = cpu_counters(file.read())
        cpu = cpu_usage(self.previous_cpu, current_cpu)
        self.previous_cpu = current_cpu
        with open("/proc/meminfo") as file:
            memory_used, memory_total = memory_values(file.read())
        gpus, processes = [], []
        try:
            result = subprocess.run(["nvidia-smi", "-q", "-x"], capture_output=True, text=True, timeout=8)
            if result.returncode:
                warnings.append("nvidia-smi 读取失败：" + (result.stderr or result.stdout).strip()[:500])
            else:
                gpus, processes = self.parse_gpus(result.stdout, time.monotonic())
        except FileNotFoundError:
            warnings.append("未找到 nvidia-smi；CPU 和内存监控仍可使用。")
        except subprocess.TimeoutExpired:
            warnings.append("nvidia-smi 响应超时，未获得本次 GPU 数据。")
        except (ET.ParseError, ValueError) as error:
            warnings.append("GPU 数据解析失败：" + str(error)[:300])
        return {"timestamp": time.time(), "hostname": socket.gethostname(), "cpuPercent": cpu,
                "cpuCores": os.cpu_count() or 1, "memoryUsed": memory_used, "memoryTotal": memory_total,
                "loadAverage": list(os.getloadavg()), "gpus": gpus, "processes": processes, "warnings": warnings}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--interval", type=float, default=3)
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args()
    interval = min(60, max(1, args.interval))
    sampler = Sampler()
    running = True

    def stop(signum, frame):
        nonlocal running
        running = False

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    while running:
        start = time.monotonic()
        try:
            print(json.dumps(sampler.sample(), ensure_ascii=False, allow_nan=False), flush=True)
        except BrokenPipeError:
            break
        except OSError as error:
            print("Linux /proc 采样失败：" + str(error), file=__import__("sys").stderr, flush=True)
            break
        if args.once:
            break
        deadline = start + interval
        while running and time.monotonic() < deadline:
            time.sleep(min(0.2, max(0, deadline - time.monotonic())))


if __name__ == "__main__":
    main()
