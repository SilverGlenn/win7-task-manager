plasma-systemmonitor
====================

An application for monitoring system resources.

plasma-systemmonitor provides an interface for monitoring system sensors,
process information and other system resources. It is built on top of the faces
system also used to provide widgets for plasma-desktop and makes use of the
ksystemstats daemon to provide sensor information. It allows extensive
customisation of pages, so it can be made to show exactly which data people
want to see.

## Windows 7 Task Manager Recreation (`taskmgr.exe`)

This repository has been customized to provide a pixel-accurate recreation of **Windows 7 Task Manager** (`taskmgr.exe`) powered by KDE's `KSysGuard` / `ksystemstats` backend and `plasma-systemmonitor` components, along with a native-feeling Windows 7 **Overview** tab.

### Features & Tab Mapping

1. **Overview Tab (`src/Win7OverviewTab.qml` — `overview.page` equivalent)**:
   - Dual classic Windows 7 sunken vertical LED bar gauges (`CPU` with optional red kernel time segments, and `Memory`) paired with a combined `Resource History (CPU / Memory)` scrolling green-grid graph.
   - `System & Memory` and `Disk & Network` Win7 group boxes displaying live `Physical (MB)`, `Cached / Swap`, `Cores / Processes`, `Up Time`, `Disk Space`, `Disk Read/Write`, `Net Down`, and `Net Up` rates from `ksystemstats`.
   - `Top Resource Processes` Win7 list view (`Image Name`, `PID`, `CPU %`, `Memory %`, `Memory`) with sortable percentages to one decimal place and Aero scrollbars, sorted by memory usage descending (`ProcessSortFilterModel.ViewUser`), with `[UAC Shield] Processes...`, `End Process`, and `New Task...` action buttons.
2. **Applications Tab (`src/Win7ApplicationsTab.qml` — `applications.page` equivalent)**:
   - Displays running desktop applications via `KSysGuard::ApplicationDataModel` (with automatic fallback to `ProcessDataModel` + `ProcessSortFilterModel.ViewOwn` when systemd application cgroups are unavailable).
   - Classic `Task` and `Status` (`Running`) columns, `Large Icons` / `Small Icons` / `Details` view modes (`View` menu), right-click context menu (`Switch To`, `Bring To Front`, `Minimize`, `Maximize`, `Tile Horizontally`, `Tile Vertically`, `Cascade`, `End Task`, `Go To Process`), empty-area context menu (`New Task (Run...)`), and bottom-right `End Task`, `Switch To`, and `New Task...` buttons.
3. **Processes Tab (`src/Win7ProcessesTab.qml` — `processes.page` equivalent)**:
   - Full process table (`Image Name`, `User Name`, `CPU %`, `Memory %`, `Memory (Private Working Set)` in `K`, `Description`) backed by `ProcessDataModel`, `ProcessSortFilterModel`, and `ProcessController`.
   - CPU is normalized to whole-system capacity; memory percentage is the process share of physical RAM. Both percentages show one decimal place.
   - `[UAC Shield] Show processes from all users` button (`ViewOwn` <-> `ViewAll`) and `End Process` button with Windows 7 confirmation dialog.
   - Right-click context menu (`Open File Location`, `End Process`, `End Process Tree`, `Debug`, `Set Priority` -> `Realtime`/`High`/`Above Normal`/`Normal`/`Below Normal`/`Low`/`Custom Priority / Scheduler...` via `ReniceDialog`, `Set Affinity...` via `AffinityDialog`, `Properties`) and `View -> Select Columns...` via `ColumnConfigurationDialog`.
4. **Performance Tab (`src/Win7PerformanceTab.qml` — `history.page` equivalent)**:
   - `CPU Usage` LED gauge + `CPU Usage History` scrolling green-grid graph (supports `One Graph, All CPUs` and `One Graph Per CPU`, plus `View -> Show Kernel Times` in red `#ff0000`).
   - `Memory` LED gauge + `Physical Memory Usage History` scrolling graph (`2px` `#0080ff` blue line).
   - `Physical Memory (MB)` (`Total`, `Cached`, `Available`, `Free`), `Kernel Memory (MB)` (`Paged`, `Nonpaged`), `System` (`Handles` via `/proc/sys/fs/file-nr`, `Threads` via `/proc/loadavg`, `Processes`, `Up Time`, `Commit (MB)`), and `[UAC Shield] Resource Monitor...` button.
5. **Networking Tab (`src/Win7NetworkingTab.qml`)**:
   - Dynamic auto-scaling scrolling network utilization graph (`0` to `1%` / `5%` / `10%` / `25%` / `50%` / `100%`) with `#ffff00` total utilization and `#ff0000` sent utilization traces.
   - Classic 4-column adapter table (`Adapter Name`, `Network Utilization`, `Link Speed`, `State`).
6. **Custom User Pages (`Page.PagesModel`)**:
   - Any additional custom `.page` files created by the user in `PagesModel` automatically appear as additional tabs in the tab bar and render via `Page.EditablePage`.
7. **Menus, Context Menus, Dialogs & Status Bar (`src/Main.qml`, `src/GlobalMenu.qml`, `src/Win7Menu.qml`, `src/Win7MenuItem.qml`, `src/Win7MenuSeparator.qml`)**:
   - Pixel-accurate Windows 7 Aero menu bar (`File`, `Options`, `View`, contextual `Windows` on `Applications` tab, `Help`) and dropdown/context menus (`#979797` outer border, `2px` `#f5f5f5` inner frame, `26px` `#f1f1f1` icon/check gutter with `#e2e3e3`/`#ffffff` etched divider, `22x22` `#aecff7` check/radio indicator boxes, `#f2f7fd`->`#dde9f8` Aero hover highlight, `4px` drop shadow, `Create New Task` (`Run...`) dialog (`src/Win7NewTaskDialog.qml`), `About Windows Task Manager` dialog (`src/Win7AboutDialog.qml`), and 3-pane sunken status bar (`Processes: X`, `CPU Usage: Y%`, `Physical Memory: Z%`) with bottom-right resize grip dots).

### Building, Running & Testing

> **Important Memory Constraint**: Always compile with `-j2` (`cmake --build build -j2`) rather than `-j$(nproc)` to avoid excessive RAM consumption, and do not leave the QEMU Windows 7 VM running while compiling.

```bash
# Configure (if build/ does not exist)
cmake -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo

# Build (use -j2 to keep RAM usage low)
cmake --build build -j2

# Run standalone
QML_IMPORT_PATH="$PWD/build/bin" ./build/bin/plasma-systemmonitor

# Run unit tests
ctest --test-dir build --output-on-failure

# Capture offscreen screenshots of all 5 tabs (no X11/Wayland focus interruption)
QT_QPA_PLATFORM=offscreen WIN7_SCREENSHOT_DIR="/tmp" QML_IMPORT_PATH="$PWD/build/bin" ./build/bin/plasma-systemmonitor
```

See [AGENTS.md](AGENTS.md) for detailed architecture notes, component specifications, and handoff instructions for AI agents.

<!--
SPDX-FileCopyrightText: 2020 Arjen Hiemstra <ahiemstra@heimr.nl>
SPDX-License-Identifier: BSD-3-Clause
-->
