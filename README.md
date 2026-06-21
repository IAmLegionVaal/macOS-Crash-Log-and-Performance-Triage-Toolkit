# macOS Crash Log and Performance Triage Toolkit

A macOS support toolkit for collecting crash and performance evidence and applying targeted application or user-interface repairs.

## Diagnostic script

```bash
chmod +x src/macos_crash_performance_triage.sh
sudo ./src/macos_crash_performance_triage.sh --hours 24 --top 25
```

The diagnostic script collects crash, spin and hang reports, memory pressure, CPU use, thermal state and recent performance events.

## Repair script

Restart user-interface helpers:

```bash
chmod +x src/macos_performance_repair.sh
./src/macos_performance_repair.sh --restart-ui
```

Restart one application:

```bash
./src/macos_performance_repair.sh --restart-app /Applications/Example.app
```

Terminate one hung process owned by the logged-in user:

```bash
./src/macos_performance_repair.sh --terminate-pid 1234
```

Add `--force` only when the selected process ignores the normal termination request. Preview any action with `--dry-run`.

## What the repair does

- Restarts Dock, SystemUIServer and selected user helper processes.
- Gracefully quits and reopens one selected application bundle.
- Can terminate one selected process owned by the logged-in user.
- Refuses low system PIDs and system-owned processes.
- Supports confirmation prompts, dry-run, logs and post-repair verification.

## Safety and limitations

Save open work before restarting an application or terminating a process. Kernel, hardware, thermal, storage and memory faults require separate investigation and are not hidden by the repair workflow.

## Author

Dewald Pretorius — L2 IT Support Engineer
