# macOS Crash Log and Performance Triage Toolkit

A read-only Bash toolkit for collecting crash reports, spin and hang reports, memory pressure, CPU use, thermal state, and recent performance events.

## Usage

```bash
chmod +x src/macos_crash_performance_triage.sh
sudo ./src/macos_crash_performance_triage.sh --hours 24 --top 25
```

## Checks performed

- Recent user and system diagnostic reports
- Top CPU and memory processes
- Memory pressure, virtual memory, swap, load, and thermal indicators
- Recent crash, hang, watchdog, jetsam, and memory-pressure events
- Text, CSV, and JSON reports

## Safety

The script never kills, samples, spins, renices, restarts, or modifies applications and services.

## Author

Dewald Pretorius — L2 IT Support Engineer
