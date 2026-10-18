# Agent Handoff & Architecture Guide (`plasma-systemmonitor` — Windows 7 Task Manager)

This guide describes the accepted Windows 7 UI baseline, its current implementation, verification steps, and local deployment. Keep it synchronized with `CLAUDE.md`; update `README.md` for user-facing behavior.

---

## 1. Critical Operational & Memory Constraints

1. **Low-Memory Compilation (`-j2` ONLY)**:
   - **NEVER** run `cmake --build build` with `-j$(nproc)` or high parallelism. Always use:
     ```bash
     cmake --build build -j2
     ```
2. **Windows 7 QEMU VM (`/home/siru/VMs/windows7`)**:
   - The reference Windows 7 VM (`win7.qcow2`) is configured for `4096M` RAM in `/home/siru/VMs/windows7/start.sh`.
   - **NEVER** leave QEMU running while compiling C++/QML targets in this repository.
   - Reference screenshots captured from the VM are stored in `/home/siru/.gemini/antigravity-cli/brain/d3805405-643d-4fb9-8bb9-b8ae656a49f5/scratch/` (`crop_processes.png`, `crop_performance.png`, `crop_perf_kernel.png`, `crop_networking.png`, `crop_users.png`, `crop_menu_*.png`, `crop_ctx_*.png`).
   - Verify the contents before using a reference: `crop_processes.png` actually shows Applications, and `crop_performance.png` shows Services. Use `crop_perf_kernel.png` for Performance and `crop_menu_options.png` / `crop_ctx_proc.png` for the visible Processes layout. Networking's saved reference has no active adapter; an active Linux adapter should still display its live graph.
3. **Unobtrusive Screenshot Verification (`WIN7_SCREENSHOT_DIR`)**:
   - Avoid stealing X11/Wayland active window focus with `spectacle -a` while the user is working.
   - `src/main.cpp` includes built-in offscreen screenshot capture triggered via the `WIN7_SCREENSHOT_DIR` environment variable:
     ```bash
     QT_QPA_PLATFORM=offscreen WIN7_SCREENSHOT_DIR="/tmp" QML_IMPORT_PATH="$PWD/build/bin" ./build/bin/plasma-systemmonitor
     ```
   - This renders and saves `our_overview.png`, `our_applications.png`, `our_processes.png`, `our_performance.png`, `our_networking.png`, and open-menu verification images (`our_menu_file.png`, `our_menu_options.png`, `our_menu_view.png`, `our_menu_windows.png`, `our_menu_help.png`, `our_ctx_proc.png`, `397x421` each) using `QQuickWindow::grabWindow()` without opening a visible desktop window.

---

## 2. File Map & Component Responsibilities

### C++ Backend & Entry Point

- [`CMakeLists.txt`](CMakeLists.txt):
  - Configured to build cleanly against the host's Qt `6.10.x` and KF6 `6.24.x` / Plasma `6.6.x` libraries (`PROJECT_DEP_VERSION "6.6.0"`, `QT_MIN_VERSION "6.10.0"`, `KF6_MIN_VERSION "6.24.0"`, and `KF6KirigamiAddons` marked `TYPE RUNTIME`).
- [`src/CMakeLists.txt`](src/CMakeLists.txt):
  - Registers all `Win7*.qml` components in `ecm_target_qml_sources(plasma-systemmonitor ...)`.
- [`src/main.cpp`](src/main.cpp):
  - Initializes the font database before registering the Windows 7 reference Segoe UI faces. Loads the newer Segoe UI files only as a fallback, because duplicate family names override the reference faces. Regular UI text uses `12px` (9pt at 96 DPI).
  - Uses `Windows Task Manager` in `KAboutData` and the main QML window title. Clears Qt's application display name to avoid appending a duplicate suffix to dialog titles.
  - Loads `utilities-system-monitor.png` at 16/24/32/48/256 sizes from `/usr/share/icons/Windows 7 Aero/apps/`, falling back to the current icon theme. It does not render the icon procedurally.
  - Uses `KDBusService(KDBusService::Multiple)` so `./build/bin/plasma-systemmonitor` can run alongside an installed `/usr/bin/plasma-systemmonitor` instance without exiting early.
  - Supports `WIN7_SCREENSHOT_DIR` for automated offscreen tab and menu capture.
  - Captures tabs and dialogs sequentially, using `Main.debugCaptureWindow` to select the intended dialog. Do not schedule independent capture steps: their timers can overlap and mislabel the images.
- [`src/ToolsModel.h`](src/ToolsModel.h) & [`src/ToolsModel.cpp`](src/ToolsModel.cpp):
  - Exposes `Q_INVOKABLE void runCommand(const QString &command)` backed by `KIO::CommandLauncherJob` to power `File -> New Task (Run...)`.
  - Provides external tool launching (`trigger(id)`) and themed dialog icons (`setWindowIconByName`). Handles/Threads sampling belongs to `Win7SystemStatistics`.

- [`src/Win7SnapshotModel.h`](src/Win7SnapshotModel.h) & [`src/Win7SnapshotModel.cpp`](src/Win7SnapshotModel.cpp):
  - Cache process/application model rows, header roles, and values until the shared update clock refreshes them. Stable PID identities preserve indexes and scroll position when rows change. Views must read the snapshot rather than the live backend to honor Paused.

- [`src/Win7SystemStatistics.h`](src/Win7SystemStatistics.h) & [`src/Win7SystemStatistics.cpp`](src/Win7SystemStatistics.cpp):
  - Read real system-wide Linux counts: Handles = allocated minus unused from `/proc/sys/fs/file-nr` (open file descriptions); Threads = the total after `/` in the fourth `/proc/loadavg` field.
  - Expose sampled 64-bit counts as `QVariant` properties. Missing/malformed data becomes invalid and displays `—`; each source can fail or recover independently. Do not substitute estimates or clamp real zero values.
  - Have no polling timer. `Win7PerformanceTab.refreshNow()` calls `refresh()` on each shared clock/manual refresh, before its visibility guard. Startup sampling happens only while unpaused. The alternative proc-root constructor supports fixture-based tests.

- [`src/Win7NetworkProcessModel.h`](src/Win7NetworkProcessModel.h) & [`src/Win7NetworkProcessModel.cpp`](src/Win7NetworkProcessModel.cpp):
  - Consume the existing `ksgrd_network_helper` one-second TCP/UDP byte reports. Rates use the latest report; cumulative totals add each report exactly once. No permission or capability changes are performed. Unavailable rates/totals display `—`.
  - Start monitoring on the first Networking visit and keep collecting until exit. Publish display rows only through the shared refresh/manual clock; sorting uses the displayed snapshot. Helper output and background scan completion must never publish rows directly, or Paused breaks.
  - Use PID plus `/proc/<pid>/stat` start time to prevent inherited totals after PID reuse. Show connected processes and processes with traffic during the past ten seconds.
  - Run connection scans via Qt Concurrent, guarded by `m_scanPending` until the watcher's finished handler consumes the result. Do not replace a finished future before its queued completion signal is handled.
- [`src/Win7NetworkConnections.h`](src/Win7NetworkConnections.h) & [`src/Win7NetworkConnections.cpp`](src/Win7NetworkConnections.cpp):
  - Read IPv4/IPv6 TCP/UDP sockets through `NETLINK_SOCK_DIAG` and map socket inodes to readable `/proc/<pid>/fd` entries on a background thread. TCP activity ages identify the latest observed peer. A single connected UDP peer is identifiable; multiple UDP peers and unconnected UDP must not be guessed.
  - Last IP is best effort; short-lived sockets and permission-limited descriptor ownership may be unavailable. Preserve the latest observed address while the process lives. Listening sockets do not count as connected peers.

### QML Shell, Menus & Reusable Win7 Controls

- [`src/Main.qml`](src/Main.qml):
  - `397x421` default window dimensions matching the Windows 7 Task Manager client area.
  - Top 19px Windows 7 Aero menu bar (`#fefeff` -> `#f2f5fa` -> `#e5eaf5` -> `#d4dbed` -> `#e1e6f6`, bottom `#b6bccc` border) with `File`, `Options`, `View`, contextual `Windows` (visible only when `currentTabId === "applications"`), and `Help`, plus authentic pressed `#4b4d54` inset button frame and hover-to-switch open menus.
  - Classic Win32 tab strip with square, non-antialiased corners and integer pixel widths to avoid white seams (`21px` selected tab overlapping the `#898c95` content pane border by `1px` with a dotted focus rectangle).
  - Maps the built-in pages into 5 tabs (`Overview`, `Applications`, `Processes`, `Performance`, `Networking`) and appends any non-hidden custom user pages from `Page.PagesModel`.
  - Bottom 23px 3-pane sunken status bar (`Processes: <N>`, `CPU Usage: <X>%`, `Physical Memory: <Y>%`) with a classic 3x3 diagonal resize grip.
- [`src/GlobalMenu.qml`](src/GlobalMenu.qml):
  - Contains a limited `Qt.labs.platform` menu component for File, Options, Refresh Now, and Help. The current shell does not instantiate it; `Main.qml` owns the active full menu bar and contextual Windows menu.
- [`src/Win7Menu.qml`](src/Win7Menu.qml), [`src/Win7MenuItem.qml`](src/Win7MenuItem.qml), & [`src/Win7MenuSeparator.qml`](src/Win7MenuSeparator.qml):
  - Pixel-accurate Windows 7 popup menu and context menu components (`1px` `#979797` outer border, `2px` `#f5f5f5` inner frame, `26px` `#f1f1f1` icon/check gutter at `x: 3..28`, `2px` `#e2e3e3`/`#ffffff` vertical gutter divider at `x: 29..30`, `#f0f0f0` menu face, `4px` right/bottom drop shadow, `22px` item height, `22x22` `#aecff7` rounded check/radio indicator box with `#0c12a1` checkmark or radial radio bullet, right-aligned `\t` shortcut column, `4x7` black submenu arrow, `8px` etched separator starting at `x: 28` after the gutter, and `property bool shown` for conditional tab-specific submenus).
- [`src/Win7Button.qml`](src/Win7Button.qml):
  - Win7 Aero command button with `75px` minimum implicit width and `23px` height for 9pt Segoe UI, per [Microsoft's control sizing guide](https://learn.microsoft.com/en-us/windows/win32/uxguide/vis-layout#recommended-sizing-and-spacing). Explicit padding/insets prevent the host Qt Quick theme from changing the geometry. Uses `3px` rounded corners, a shaded inner rim, `#f2f2f2`/`#ebebeb`/`#dddddd`/`#cfcfcf` split face gradient, layered cyan default ring, blue hover/pressed states, a keyboard focus rectangle, mnemonic underline rendering, and a UAC shield icon.
- [`src/Win7GroupBox.qml`](src/Win7GroupBox.qml):
  - Pixel-accurate Win7 group box (`1px` `#d5dfe5` border with `3px` radius and `#000000` `Segoe UI` `12px` title interrupting the top border at `x: 9`).
- [`src/Win7UpdateClock.qml`](src/Win7UpdateClock.qml) & [`src/Win7Sensor.qml`](src/Win7Sensor.qml):
  - One shared refresh cycle uses 500ms (High), 2000ms (Normal/default), 4000ms (Low), or 0 (Paused). The clock samples sensors before refreshing table snapshots and graphs. Sensor values are latched between ticks; F5 samples once without leaving Paused. Tab graphs disable their independent timers.
- [`src/Win7ScrollBar.qml`](src/Win7ScrollBar.qml):
  - `17px` Aero scrollbar with arrow buttons, a beveled thumb and grip. Overview and Processes reserve space for both axes as needed so controls do not cover row values or one another.
- [`src/Win7Gauge.qml`](src/Win7Gauge.qml):
  - Pixel-accurate Win7 vertical LED bar gauge (`2px` sunken 3D bevel `#a0a0a0`/`#696969` top-left, `#ffffff`/`#e3e3e3` bottom-right, `#000000` fill, dual `16px` columns separated by a `2px` gap, `2px` segment height + `1px` gap, `#008000` checkerboard dithered unlit segments, `#00ff00` lit segments, `#ff0000` kernel segments, and bottom `#00ff00` readout text).
- [`src/Win7HistoryGraph.qml`](src/Win7HistoryGraph.qml):
  - Pixel-accurate Win7 scrolling history chart (`2px` sunken 3D bevel, `#000000` background, `#008040` `12px` gridlines scrolling left by `2px` per tick, `#00ff00` primary line, `#ff0000` kernel/secondary line, and `2px` `#0080ff` tertiary memory line).
  - Pre-populates history buffer when the first live non-zero sensor reading arrives so graphs display a continuous line immediately on startup.
- [`src/Win7NewTaskDialog.qml`](src/Win7NewTaskDialog.qml) & [`src/Win7AboutDialog.qml`](src/Win7AboutDialog.qml):
  - `Create New Task` (`Run...`, `398x173` client area) and `About Windows Task Manager` (`459x374` client area) modal dialogs, with proportions measured from the VM references.
- [`src/table/BaseCellDelegate.qml`](src/table/BaseCellDelegate.qml):
  - Updated selection/hover highlight to the Windows 7 Aero icy-blue gradient (`#dcebfc` -> `#c1dbfc` with `#7da2ce` border).

### Tab Views

- [`src/Win7OverviewTab.qml`](src/Win7OverviewTab.qml):
  - Native-feeling Windows 7 **Overview** tab combining `CPU`, `GPU`, `RAM`, and `SWAP` `Win7Gauge`s in that order, `Resource History (CPU / Memory)` `Win7HistoryGraph`, `System & Memory` and `Disk & Network` `Win7GroupBox`es, and `Top Resource Processes` list (`ProcessDataModel` → `Win7SnapshotModel` → `ProcessSortFilterModel.ViewUser`, sorted by Memory % descending). Its sortable `CPU %` and `Memory %` columns reuse `Win7ProcessFormat.js`; the derived memory percentage sorts on the backend memory attribute. Both axes use `Win7ScrollBar` and the header tracks horizontal scrolling.
  - GPU uses `gpu/all/usage`; RAM/SWAP bars use physical/swap usage relative to capacity and show the used amount. Missing GPU/swap readings display `—`; zero configured swap is valid and displays 0 MB with an empty bar. Gauge widths scale from 58 to 74px, and the history title shortens in compact windows. All readings use the shared sampled `Win7Sensor` values to honor Paused.
- [`src/Win7ApplicationsTab.qml`](src/Win7ApplicationsTab.qml):
  - Uses `Process.ApplicationDataModel` → `Win7SnapshotModel` → `KItemModels.KSortFilterProxyModel` (filtering out empty `appName` and system slices `session.slice`/`background.slice`/`services`), with a separate snapshot for the `Process.ProcessDataModel` (`ViewOwn`) fallback. Read mapped indexes from the snapshot, not the original backend model.
- [`src/Win7ProcessesTab.qml`](src/Win7ProcessesTab.qml):
  - Uses `Process.ProcessDataModel` → `Win7SnapshotModel` → `Table.ProcessSortFilterModel` (`ViewOwn` by default, `ViewAll` when `Show processes from all users` is clicked) and `Process.ProcessController`. Select Columns, priority, affinity, properties, and termination confirmation use custom windows declared in this file.
  - Shows `CPU %` and `Memory %` with one decimal place. CPU is normalized against the backend maximum; memory is process KiB converted to bytes divided by `memory/physical/total`. The derived `memoryPercent` column sorts using `memory` and must never be sent as a backend attribute. `Win7ProcessFormat.js` handles percentage formatting and unavailable totals.
- [`src/Win7PerformanceTab.qml`](src/Win7PerformanceTab.qml):
  - Uses `Win7Sensor` wrappers around `Sensors.Sensor` for CPU, per-core CPU (`cpu/cpu*/usage`, `cpu/cpu*/system`), physical memory, cache, buffer, free, swap, and uptime. Handles/Threads use `Win7SystemStatistics` for real `/proc` counts; Windows kernel-memory fields remain estimates. Procfs access stays in C++ rather than QML `XMLHttpRequest`. Per-core history currently displays at most eight graphs. Resource Monitor switches to Overview.
- [`src/Win7NetworkingTab.qml`](src/Win7NetworkingTab.qml):
  - Keeps three vertically stacked sections visible: graph, Processes, Devices. Proportional heights and minimum sizes support the original 397×421 client and larger windows; there is no section-switching control.
  - Uses `Win7Sensor` for aggregate `network/all/*` readings and `network/wlp2s0/*` for the optional wireless label/address. The graph scale uses powers of ten with a 1 Mbps minimum. The adapter table has Adapter Name, Network Utilization, Link Speed, and State columns; 100 Mbps and Connected are currently fixed display values.
- [`src/Win7NetworkProcessesView.qml`](src/Win7NetworkProcessesView.qml):
  - Presents sortable/resizable Image Name, PID, Send, Receive, Total, Sent, Received, Connections, Last IP, Port, and Protocol columns. Both axes reserve Aero scrollbar space. The footer shows the selected peer and Go to Process; double-clicking also selects the PID in the Processes tab.

---

## 3. Important KSysGuard / QML Gotchas to Keep in Mind

1. **`QAbstractItemModel::rowCount()` is NOT a reactive QML property**:
   - `rowCount()` is a C++ `Q_INVOKABLE` without a `NOTIFY` signal. Binding `property int count: model.rowCount()` evaluates once at startup (when `0`) and never updates.
   - Always bind to `ListView.count` or update a property inside `Connections` on `onRowsInserted`, `onRowsRemoved`, `onModelReset`, and `onLayoutChanged`.
2. **Asynchronous Column Registration in `ProcessDataModel` / `ProcessSortFilterModel`**:
   - `ProcessDataModel` populates its columns asynchronously when `ksystemstats` responds over D-Bus. Calling `filterModel.sort(col, order)` in `Component.onCompleted` runs when `columnCount() == 0`, which resets `sortColumn` to `-1`.
   - Always re-apply `sort(root.sortColumn, root.sortOrder)` inside `Connections { target: filterModel; function onColumnMappingChanged() { ... } }` and via a short `Timer` (`~700ms`) after `onRowsInserted` so rows are sorted after their initial attribute values arrive.
3. **`ViewOwn` and `ViewUser` Require `"uid"` in `enabledAttributes`**:
   - `ProcessSortFilterModel::filterAcceptsRow()` checks `m_uidColumn`. Any `ProcessDataModel` paired with `ProcessSortFilterModel` using `ViewOwn`, `ViewUser`, or `ViewSystem` **must** include `"uid"` in `enabledAttributes` (and `"uid"` in `hiddenAttributes` so it doesn't take a visible column slot).

4. **Shared sampling and Paused behavior**:
   - `Win7UpdateClock.sampleRequested` latches sensor values first; `refreshed` then calls `Main.refreshViews()` to sample model snapshots and advance visible graphs. Keep built-in graph timers disabled (`running: false`) to prevent double sampling.
   - Display rows, header roles, values, and application icons must come from `Win7SnapshotModel`. Reading the live backend bypasses Paused. Use `ProcessDataModel.PIDs` as the snapshot key role and bind `initialUpdatesEnabled` to the clock being unpaused.
   - Initial asynchronous data may populate a new view while unpaused. Once initialized, emptying a list must not re-enable automatic startup sampling. `TestWin7Updates` covers this regression and persistent indexes across membership changes.
   - Pause freezes the built-in display; `ksystemstats` can continue supplying other consumers. A refresh uses the most recent available backend readings.

---

## 4. Current User-Local Installation

- The installed prefix is `/home/siru/.local/lib/win7-task-manager`; the existing build is configured with that `CMAKE_INSTALL_PREFIX`. After a verified build, run `cmake --install build` to update the installed app.
- `/home/siru/.local/bin/plasma-systemmonitor` wraps the installed executable and supplies its private QML import and data paths. Desktop launches use this wrapper, so rebuilding alone does not update the app the user opens from the Start menu.
- Local overrides in `~/.local/share/applications/` and `~/.local/share/kglobalaccel/` keep the desktop ID `org.kde.plasma-systemmonitor.desktop`, display **Task Manager**, and use **Ctrl+Shift+Esc**. Preserve these overrides when reinstalling; copy them over the corresponding desktop files inside the private prefix after CMake installation.

---

## 5. Verification and Baseline Documentation

- Run `QT_QPA_PLATFORM=offscreen ctest --test-dir build --output-on-failure`. The suites are `appstreamtest`, `TestPageManager`, `TestWin7Updates`, `TestWin7SystemStatistics`, and `TestWin7NetworkProcesses`. Update tests cover High/Normal/Low timing, pause/manual refresh/resume, frozen values/membership, and persistent row indexes. Statistics tests cover procfs parsing, 64-bit counts, independent failures/recovery, and values held until explicit refresh. Network tests cover exact byte accounting, pause, malformed/unavailable data, PID reuse, peer attribution, and real IPv4/IPv6 loopback sockets. Qt page tests write to `~/.qttest` even when `XDG_DATA_HOME` is overridden.
- The screenshot command in section 1 also captures sorted/scrolled tables, dialogs, `our_<tab>_paused.png` / `our_<tab>_paused_again.png` for all five built-in tabs, and `our_overview_refreshed.png` / `our_overview_resumed.png`. Paused pairs should be byte-identical; the manually refreshed Overview should differ. See the comparison snippet in `README.md`.
- Networking adds `our_network_processes_scrolled.png` and a 780×660 `our_networking_large.png` to verify all three stacked sections and the remote-IP columns. These can contain live peer IPs and the wireless network name; keep local QA images out of commits.
- Overview adds `our_overview_minimum.png` (380×395) and `our_overview_large.png` (780×660) to verify the four-gauge row and history at both size limits.
- `docs/screenshots/performance.png` records the accepted offscreen client-area appearance at 100% scale. Update it only after visually checking intentional UI changes.
- Keep implementation status accurate: target-window management remains preliminary; Debug/UAC virtualization/dump creation are disabled; End Process Tree currently force-kills only the selected PID. Do not document these as complete features.
- The local wrapper, Task Manager name, and Ctrl+Shift+Esc registration are user configuration. The checked-in desktop template still uses System Monitor / Meta+Esc, so plain CMake installation on another machine does not reproduce those local overrides.
