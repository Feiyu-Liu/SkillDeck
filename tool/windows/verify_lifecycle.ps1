param(
  [Parameter(Mandatory=$true)][string]$Root,
  [ValidateSet('all', 'window', 'tray', 'menu', 'session', 'restart')][string]$Scenario = 'window'
)

# Run in an interactive scheduled task. Only the disposable test-identity
# executable is accepted; never close, kill, or alter the installed App.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$AppPath = Join-Path $Root 'skilldeck-app\build\windows\x64\runner\Release\SkillDeck.exe'
$OutputDirectory = Join-Path $Root 'dist\lifecycle'
$app = Get-Item -LiteralPath $AppPath
if ($app.VersionInfo.ProductName -ne 'SkillDeck Lifecycle Test') {
  throw 'This harness requires the isolated SkillDeck Lifecycle Test identity.'
}
if (@(Get-Process SkillDeck -ErrorAction SilentlyContinue).Count -ne 0) {
  throw 'Exit existing SkillDeck instances before running this harness.'
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
if ($Scenario -eq 'all') {
  foreach ($case in @('window', 'tray', 'menu', 'session', 'restart')) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Root $Root -Scenario $case
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  }
  exit 0
}
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class LifecycleWin32 {
  public delegate bool EnumProc(IntPtr hwnd, IntPtr state);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc callback, IntPtr state);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hwnd, StringBuilder value, int length);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hwnd, uint msg, IntPtr wparam, IntPtr lparam);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hwnd, uint msg, IntPtr wparam, IntPtr lparam);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern IntPtr SetActiveWindow(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool GetMenuItemRect(IntPtr window, IntPtr menu, uint index, out Rect rect);
  [StructLayout(LayoutKind.Sequential)] public struct Point { public int x, y; }
  [DllImport("user32.dll")] public static extern bool ScreenToClient(IntPtr window, ref Point point);
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern uint RegisterWindowMessage(string name);
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct NotifyIconData {
    public uint size; public IntPtr hwnd; public uint id, flags, callback; public IntPtr icon;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string tip;
    public uint state, stateMask;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=256)] public string info;
    public uint version;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=64)] public string title;
    public uint infoFlags; public Guid guid; public IntPtr balloon;
  }
  [StructLayout(LayoutKind.Sequential)] public struct IconIdentifier { public uint size; public IntPtr hwnd; public uint id; public Guid guid; }
  [DllImport("shell32.dll", CharSet=CharSet.Unicode)] public static extern bool Shell_NotifyIcon(uint message, ref NotifyIconData data);
  [DllImport("shell32.dll")] public static extern int Shell_NotifyIconGetRect(ref IconIdentifier identifier, out Rect rect);
  public static void RemoveTestIcon(IntPtr host) {
    var data = new NotifyIconData { size=(uint)Marshal.SizeOf(typeof(NotifyIconData)), hwnd=host, id=0x04000001, tip="", info="", title="" };
    if (!Shell_NotifyIcon(2, ref data)) throw new Exception("Unable to remove the test notification icon.");
  }
  public static bool HasTestIcon(IntPtr host) {
    var data = new IconIdentifier { size=(uint)Marshal.SizeOf(typeof(IconIdentifier)), hwnd=host, id=0x04000001 };
    Rect rect; return Shell_NotifyIconGetRect(ref data, out rect) == 0;
  }
  [StructLayout(LayoutKind.Sequential)] public struct Rect { public int left, top, right, bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct MonitorInfo { public int cbSize; public Rect monitor, work; public uint flags; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out Rect rect);
  [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);
  [DllImport("user32.dll")] public static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
  public static Rect Bounds(IntPtr hwnd) { Rect rect; GetWindowRect(hwnd, out rect); return rect; }
  public static Rect WorkArea(IntPtr hwnd) {
    var info = new MonitorInfo { cbSize=Marshal.SizeOf(typeof(MonitorInfo)) };
    GetMonitorInfo(MonitorFromWindow(hwnd, 2), ref info); return info.work;
  }
  public static void ClickMenuItem(IntPtr popup, uint index) {
    var menu = SendMessage(popup, 0x01E1, IntPtr.Zero, IntPtr.Zero);
    Rect rect;
    if (menu == IntPtr.Zero || !GetMenuItemRect(IntPtr.Zero, menu, index, out rect)) {
      throw new Exception("Cannot locate the native menu item.");
    }
    uint pid; uint target = GetWindowThreadProcessId(popup, out pid);
    uint current = GetCurrentThreadId();
    bool attached = target != current && AttachThreadInput(current, target, true);
    try {
      SetForegroundWindow(popup); SetActiveWindow(popup);
      var point = new Point { x=(rect.left+rect.right)/2, y=(rect.top+rect.bottom)/2 };
      SetCursorPos(point.x, point.y);
      System.Threading.Thread.Sleep(150);
      ScreenToClient(popup, ref point);
      var coords = new IntPtr((point.y << 16) | (point.x & 0xffff));
      SendMessage(popup, 0x0200, IntPtr.Zero, coords);
      PostMessage(popup, 0x0201, new IntPtr(1), coords);
      System.Threading.Thread.Sleep(100);
      PostMessage(popup, 0x0202, IntPtr.Zero, coords);
    } finally { if (attached) AttachThreadInput(current, target, false); }
  }
  public static IntPtr Window(uint processId, string className="FLUTTER_RUNNER_WIN32_WINDOW") {
    IntPtr result = IntPtr.Zero;
    EnumWindows((hwnd, state) => {
      uint pid; GetWindowThreadProcessId(hwnd, out pid);
      var cls = new StringBuilder(128); GetClassName(hwnd, cls, 128);
      if (pid == processId && cls.ToString() == className) {
        result = hwnd; return false;
      }
      return true;
    }, IntPtr.Zero);
    return result;
  }
  public static IntPtr TrayHost(uint processId) {
    var hwnd = IntPtr.Zero;
    while ((hwnd = FindWindowEx(new IntPtr(-3), hwnd, "NativeApiHostWindow", null)) != IntPtr.Zero) {
      uint pid; GetWindowThreadProcessId(hwnd, out pid);
      if (pid == processId) return hwnd;
    }
    return IntPtr.Zero;
  }
}
'@
[LifecycleWin32]::SetThreadDpiAwarenessContext([IntPtr](-4)) | Out-Null

$process = $null
$result = [ordered]@{ scenario=$Scenario; status='failed'; product=$app.VersionInfo.ProductName }
try {
  $process = Start-Process -FilePath $app.FullName -WorkingDirectory $app.DirectoryName -PassThru `
    -RedirectStandardOutput (Join-Path $OutputDirectory "$Scenario.stdout.log") `
    -RedirectStandardError (Join-Path $OutputDirectory "$Scenario.stderr.log")
  $window = [IntPtr]::Zero
  for ($attempt=0; $attempt -lt 40; $attempt++) {
    Start-Sleep -Milliseconds 500
    if ($process.HasExited) { throw "Test App exited during bootstrap ($($process.ExitCode))." }
    $window = [LifecycleWin32]::Window($process.Id)
    if ($window -ne [IntPtr]::Zero -and [LifecycleWin32]::IsWindowVisible($window)) { break }
  }
  if ($window -eq [IntPtr]::Zero -or ![LifecycleWin32]::IsWindowVisible($window)) { throw 'Main window did not become visible.' }
  $result.processId = $process.Id
  $result.dpi = [LifecycleWin32]::GetDpiForWindow($window)
  $tooltipRecords = @(Get-ChildItem -LiteralPath 'HKCU:\Control Panel\NotifyIconSettings' -ErrorAction SilentlyContinue |
    ForEach-Object { Get-ItemProperty -LiteralPath $_.PSPath } |
    Where-Object { $_.PSObject.Properties['ExecutablePath'] -and $_.ExecutablePath -eq $app.FullName })
  if ($tooltipRecords.Count -eq 0 -or @($tooltipRecords | Where-Object { $_.InitialTooltip -ne 'SkillDeck' }).Count -ne 0) {
    throw 'Windows InitialTooltip is missing or is not SkillDeck.'
  }
  $result.initialTooltip = 'SkillDeck'
  if ($Scenario -eq 'session') {
    $answer = [LifecycleWin32]::SendMessage($window, 0x0011, [IntPtr]::Zero, [IntPtr]0x1)
    if ($answer -ne [IntPtr]1) { throw 'WM_QUERYENDSESSION was rejected.' }
    [LifecycleWin32]::PostMessage($window, 0x0016, [IntPtr]::Zero, [IntPtr]0x1) | Out-Null
    Start-Sleep -Milliseconds 500
    if ($process.HasExited) { throw 'Cancelled end-session unexpectedly quit the App.' }
    [LifecycleWin32]::PostMessage($window, 0x0016, [IntPtr]1, [IntPtr]0x1) | Out-Null
    if (!$process.WaitForExit(5000)) { throw 'Confirmed end-session did not quit the App.' }
  } else {
    [LifecycleWin32]::PostMessage($window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    Start-Sleep -Milliseconds 750
    if ($process.HasExited -or [LifecycleWin32]::IsWindowVisible($window)) { throw 'Window close must hide, not quit.' }
    if ($Scenario -eq 'window') {
      $second = Start-Process -FilePath $app.FullName -WorkingDirectory $app.DirectoryName -PassThru
      if (!$second.WaitForExit(5000)) { throw 'Second launch did not hand off to existing instance.' }
    } elseif ($Scenario -eq 'tray' -or $Scenario -eq 'restart') {
      $hostWindow = [LifecycleWin32]::TrayHost($process.Id)
      if ($hostWindow -eq [IntPtr]::Zero) { throw 'Native tray host is missing.' }
      if ($Scenario -eq 'restart') {
        # Model Explorer's loss of notification icons without restarting the
        # user's shell: delete only this test icon, then notify only its watcher.
        [LifecycleWin32]::RemoveTestIcon($hostWindow)
        if ([LifecycleWin32]::HasTestIcon($hostWindow)) { throw 'Test icon was not removed.' }
        $watcher = [LifecycleWin32]::Window($process.Id, 'NativeAPITaskbarRestartWatcher')
        $message = [LifecycleWin32]::RegisterWindowMessage('TaskbarCreated')
        [LifecycleWin32]::PostMessage($watcher, $message, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
        Start-Sleep -Milliseconds 500
        if (![LifecycleWin32]::HasTestIcon($hostWindow)) { throw 'Test tray icon was not restored after TaskbarCreated.' }
      }
      # nativeapi 0.3.0 encodes TrayIcon type tag 4 in the high byte and
      # sequence 1 in the low 24 bits; replay the shell's left-click message.
      [LifecycleWin32]::PostMessage($hostWindow, 0x0401, [IntPtr]0x04000001, [IntPtr]0x0202) | Out-Null
    } else {
      $hostWindow = [LifecycleWin32]::TrayHost($process.Id)
      if ($hostWindow -eq [IntPtr]::Zero) { throw 'Native tray host is missing.' }
      $work = [LifecycleWin32]::WorkArea($window)
      [LifecycleWin32]::SetCursorPos(($work.right - 40), ($work.bottom + 12)) | Out-Null
      [LifecycleWin32]::PostMessage($hostWindow, 0x0401, [IntPtr]0x04000001, [IntPtr]0x0205) | Out-Null
      Start-Sleep -Milliseconds 750
      $menu = [LifecycleWin32]::Window($process.Id, '#32768')
      if ($menu -eq [IntPtr]::Zero) { throw 'Native tray menu did not open.' }
      $bounds = [LifecycleWin32]::Bounds($menu)
      $result.menuBounds = "$($bounds.left),$($bounds.top),$($bounds.right),$($bounds.bottom)"
      $result.workArea = "$($work.left),$($work.top),$($work.right),$($work.bottom)"
      if ($bounds.bottom -gt $work.bottom -or $bounds.right -gt $work.right -or $bounds.top -lt $work.top -or $bounds.left -lt $work.left) {
        throw 'Tray menu is outside the monitor work area.'
      }
      # Dismiss without a pick, then reopen and click the actual Quit item.
      [LifecycleWin32]::PostMessage($menu, 0x0100, [IntPtr]0x1B, [IntPtr]::Zero) | Out-Null
      Start-Sleep -Milliseconds 500
      if ([LifecycleWin32]::Window($process.Id, '#32768') -ne [IntPtr]::Zero) { throw 'Tray menu did not dismiss.' }
      [LifecycleWin32]::PostMessage($hostWindow, 0x0401, [IntPtr]0x04000001, [IntPtr]0x0205) | Out-Null
      Start-Sleep -Milliseconds 500
      $menu = [LifecycleWin32]::Window($process.Id, '#32768')
      [LifecycleWin32]::ClickMenuItem($menu, 2)
      if (!$process.WaitForExit(5000)) {
        $result.menuStillVisible = [LifecycleWin32]::IsWindowVisible($menu)
        throw 'Quit menu item did not end the App.'
      }
    }
    Start-Sleep -Milliseconds 1000
    if ($Scenario -ne 'menu') {
      if ($process.HasExited -or ![LifecycleWin32]::IsWindowVisible($window)) { throw 'Restore did not reveal the existing window.' }
      if (@(Get-Process SkillDeck -ErrorAction SilentlyContinue).Count -ne 1) { throw 'More than one App instance remains.' }
    }
  }
  $result.status = 'passed'
} catch {
  $result.error = $_.Exception.Message
} finally {
  if ($null -ne $process -and !$process.HasExited) {
    $window = [LifecycleWin32]::Window($process.Id)
    [LifecycleWin32]::PostMessage($window, 0x0016, [IntPtr]1, [IntPtr]0x1) | Out-Null
    if (!$process.WaitForExit(5000)) { Stop-Process -Id $process.Id -Force }
  }
  $result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory "$Scenario.result.json") -Encoding UTF8
}
if ($result.status -ne 'passed') { exit 1 }
