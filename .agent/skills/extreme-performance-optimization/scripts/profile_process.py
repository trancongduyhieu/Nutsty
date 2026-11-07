#!/usr/bin/env python3
"""
profile_process.py - Real-time process resource sampler & performance benchmark tool.
Usage:
    python profile_process.py --pid <PID> --duration 10 --interval 0.5
    python profile_process.py --name "python" --duration 5
"""

import sys
import time
import argparse
import subprocess

def get_process_metrics(pid):
    """Fetch process metrics using Win32 API or tasklist fallback."""
    if sys.platform == "win32":
        try:
            import ctypes
            from ctypes import wintypes

            PROCESS_QUERY_INFORMATION = 0x0400
            PROCESS_VM_READ = 0x0010

            class PROCESS_MEMORY_COUNTERS_EX(ctypes.Structure):
                _fields_ = [
                    ('cb', wintypes.DWORD),
                    ('PageFaultCount', wintypes.DWORD),
                    ('PeakWorkingSetSize', ctypes.c_size_t),
                    ('WorkingSetSize', ctypes.c_size_t),
                    ('QuotaPeakPagedPoolUsage', ctypes.c_size_t),
                    ('QuotaPagedPoolUsage', ctypes.c_size_t),
                    ('QuotaPeakNonPagedPoolUsage', ctypes.c_size_t),
                    ('QuotaNonPagedPoolUsage', ctypes.c_size_t),
                    ('PagefileUsage', ctypes.c_size_t),
                    ('PeakPagefileUsage', ctypes.c_size_t),
                    ('PrivateUsage', ctypes.c_size_t),
                ]

            class FILETIME(ctypes.Structure):
                _fields_ = [('dwLowDateTime', wintypes.DWORD), ('dwHighDateTime', wintypes.DWORD)]

            kernel32 = ctypes.windll.kernel32
            h_proc = kernel32.OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, False, pid)
            if not h_proc:
                return None

            try:
                # Memory
                pmc = PROCESS_MEMORY_COUNTERS_EX()
                pmc.cb = ctypes.sizeof(pmc)
                psapi = ctypes.windll.psapi
                mem_mb = 0.0
                private_mb = 0.0
                if psapi.GetProcessMemoryInfo(h_proc, ctypes.byref(pmc), pmc.cb):
                    mem_mb = pmc.WorkingSetSize / (1024 * 1024)
                    private_mb = pmc.PrivateUsage / (1024 * 1024)

                # CPU Times
                ct, et, kt, ut = FILETIME(), FILETIME(), FILETIME(), FILETIME()
                kernel32.GetProcessTimes(h_proc, ctypes.byref(ct), ctypes.byref(et), ctypes.byref(kt), ctypes.byref(ut))
                k_time = (kt.dwHighDateTime << 32) + kt.dwLowDateTime
                u_time = (ut.dwHighDateTime << 32) + ut.dwLowDateTime
                total_time = k_time + u_time

                return {
                    'rss_mb': mem_mb,
                    'private_mb': private_mb,
                    'cpu_time_raw': total_time,
                    'timestamp': time.time()
                }
            finally:
                kernel32.CloseHandle(h_proc)
        except Exception:
            pass

    # Generic fallback using tasklist/ps
    return None

def profile(pid, duration=10.0, interval=0.5):
    print(f"=== Profiling PID {pid} for {duration:.1f}s (sampling every {interval:.2f}s) ===")
    samples = []
    start_time = time.time()
    last_metric = get_process_metrics(pid)

    if not last_metric:
        print(f"Error: Unable to open process with PID {pid}.")
        return

    time.sleep(interval)

    while (time.time() - start_time) < duration:
        curr_metric = get_process_metrics(pid)
        if not curr_metric:
            break

        dt = curr_metric['timestamp'] - last_metric['timestamp']
        d_cpu = (curr_metric['cpu_time_raw'] - last_metric['cpu_time_raw']) / 10000000.0  # 100ns units to seconds
        # Multi-core normalized CPU %
        import os
        cpu_count = os.cpu_count() or 1
        cpu_pct = max(0.0, min(100.0, (d_cpu / dt / cpu_count) * 100.0))

        sample = {
            'time_rel': curr_metric['timestamp'] - start_time,
            'cpu_pct': cpu_pct,
            'rss_mb': curr_metric['rss_mb'],
            'private_mb': curr_metric['private_mb']
        }
        samples.append(sample)
        print(f"[{sample['time_rel']:5.1f}s] CPU: {cpu_pct:5.1f}% | RAM: {curr_metric['rss_mb']:6.1f} MB (Private: {curr_metric['private_mb']:6.1f} MB)")

        last_metric = curr_metric
        time.sleep(interval)

    if not samples:
        print("No samples collected.")
        return

    cpus = [s['cpu_pct'] for s in samples]
    rams = [s['rss_mb'] for s in samples]
    privates = [s['private_mb'] for s in samples]

    print("\n" + "=" * 50)
    print("           PERFORMANCE SUMMARY REPORT            ")
    print("=" * 50)
    print(f"Metric                 | Average    | Peak       | Minimum")
    print(f"-----------------------|------------|------------|----------")
    print(f"Normalized CPU (%)     | {sum(cpus)/len(cpus):10.2f} | {max(cpus):10.2f} | {min(cpus):8.2f}")
    print(f"Working Set RAM (MB)   | {sum(rams)/len(rams):10.2f} | {max(rams):10.2f} | {min(rams):8.2f}")
    print(f"Private Commit (MB)    | {sum(privates)/len(privates):10.2f} | {max(privates):10.2f} | {min(privates):8.2f}")
    print("=" * 50)

def main():
    parser = argparse.ArgumentParser(description="Real-time process resource sampler.")
    parser.add_argument("--pid", type=int, help="Target process PID")
    parser.add_argument("--name", type=str, help="Process name pattern (finds first matching PID)")
    parser.add_argument("--duration", type=float, default=10.0, help="Duration in seconds (default: 10s)")
    parser.add_argument("--interval", type=float, default=0.5, help="Sampling interval in seconds (default: 0.5s)")

    args = parser.parse_args()

    pid = args.pid
    if not pid and args.name:
        import subprocess
        out = subprocess.check_output(f'tasklist /fi "imagename eq {args.name}*" /fo csv /nh', shell=True, text=True)
        lines = [line.strip() for line in out.strip().splitlines() if line.strip()]
        if lines and not "No tasks are running" in lines[0]:
            first_line = lines[0].replace('"', '').split(',')
            pid = int(first_line[1])
            print(f"Discovered matching process '{first_line[0]}' with PID: {pid}")
        else:
            print(f"No active process found matching name pattern: {args.name}")
            return 1

    if not pid:
        print("Please provide --pid <PID> or --name <process_name>")
        return 1

    profile(pid, duration=args.duration, interval=args.interval)
    return 0

if __name__ == "__main__":
    sys.exit(main())
