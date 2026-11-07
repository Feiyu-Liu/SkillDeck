param(
  [Parameter(Mandatory=$true)][string]$Root,
  [switch]$Hidden
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$output = Join-Path $Root 'dist\lifecycle'
$scenario = if ($Hidden) { 'update-hidden' } else { 'update-visible' }
New-Item -ItemType Directory -Force -Path $output | Out-Null
$installer = Join-Path $Root 'dist\installers\skilldeck-0.0.1.1-windows-x64-setup.exe'
$installRoot = Join-Path $env:LOCALAPPDATA 'Programs\SkillDeckLifecycleTest'
$appPath = Join-Path $installRoot 'SkillDeck.exe'
$dataRoot = Join-Path $env:APPDATA 'Feiyu Liu\SkillDeck Lifecycle Test'
$result = [ordered]@{ scenario=$scenario; status='failed' }
$process = $null
function Save-Progress([string]$stage) {
  $result.stage = $stage
  $result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output "$scenario.progress.json") -Encoding UTF8
}
Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class UpdateControl { public IntPtr hwnd; public string label; }
public static class UpdateWin32 {
  public delegate bool EnumProc(IntPtr hwnd, IntPtr state);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc callback, IntPtr state);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumProc callback, IntPtr state);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
  [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr hwnd);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int size);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string title);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hwnd, uint msg, IntPtr wparam, IntPtr lparam);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hwnd, uint msg, IntPtr wparam, IntPtr lparam);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern IntPtr SetActiveWindow(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  public static void Click(IntPtr button) {
    var dialog = GetAncestor(button, 2);
    uint pid; uint target = GetWindowThreadProcessId(dialog, out pid);
    uint current = GetCurrentThreadId();
    bool attached = target != current && AttachThreadInput(current, target, true);
    try {
      SetForegroundWindow(dialog); SetActiveWindow(dialog);
      SendMessage(button, 0x00F5, IntPtr.Zero, IntPtr.Zero);
    } finally { if (attached) AttachThreadInput(current, target, false); }
  }
  public static string[] Describe(uint processId) {
    var labels = new List<string>();
    EnumWindows((parent, state) => {
      uint pid; GetWindowThreadProcessId(parent, out pid);
      if (pid != processId || !IsWindowVisible(parent)) return true;
      var title = new StringBuilder(512); GetWindowText(parent, title, 512);
      labels.Add(title.ToString());
      EnumChildWindows(parent, (hwnd, ignored) => {
        if (!IsWindowVisible(hwnd)) return true;
        var text = new StringBuilder(512); GetWindowText(hwnd, text, 512);
        if (text.Length > 0) labels.Add(GetDlgCtrlID(hwnd)+":"+text.ToString());
        return true;
      }, IntPtr.Zero);
      return true;
    }, IntPtr.Zero);
    return labels.ToArray();
  }
  public static UpdateControl AcceptButton(uint processId) {
    UpdateControl found = null;
    EnumWindows((parent, state) => {
      uint pid; GetWindowThreadProcessId(parent, out pid);
      if (pid != processId || !IsWindowVisible(parent) || !IsWindowEnabled(parent)) return true;
      EnumChildWindows(parent, (hwnd, ignored) => {
        int id = GetDlgCtrlID(hwnd);
        if ((id != 102 && id != 103) || !IsWindowEnabled(hwnd) || !IsWindowVisible(hwnd)) return true;
        var text = new StringBuilder(256); GetWindowText(hwnd, text, 256);
        found = new UpdateControl { hwnd=hwnd, label=text.ToString() }; return false;
      }, IntPtr.Zero);
      return found == null;
    }, IntPtr.Zero);
    return found;
  }
}
'@
try {
  if (@(Get-Process SkillDeck -ErrorAction SilentlyContinue).Count -ne 0) { throw 'Exit existing SkillDeck instances first.' }
  if ((Get-Item -LiteralPath $installer).VersionInfo.FileDescription -notlike 'SkillDeck Lifecycle Test*') { throw 'Installer is not the isolated fixture.' }
  $fixtureKey = 'HKCU:\Software\Feiyu Liu\SkillDeck Lifecycle Test\WinSparkle'
  New-Item -Path $fixtureKey -Force | Out-Null
  # The N-1 fixture performs one foreground check at 8s. Suppress a simultaneous
  # scheduled check so the test itself does not introduce a competing session.
  $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString()
  Set-ItemProperty -LiteralPath $fixtureKey -Name 'LastCheckTime' -Value $now
  Save-Progress 'installing-n1'
  $installed = Start-Process -FilePath $installer -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', "/LOG=$output\$scenario-install-n1.log") -PassThru
  # Start-Process -Wait also waits for descendants; Inno's nowait Run entry
  # launches the App. Wait for Setup alone, not for the App we are about to test.
  if (!$installed.WaitForExit(30000)) { throw 'N-1 fixture installer timed out.' }
  if ($installed.ExitCode -ne 0) { throw 'N-1 fixture installation failed.' }
  Save-Progress 'n1-installed'
  if ((Get-Item -LiteralPath $appPath).VersionInfo.ProductName -ne 'SkillDeck Lifecycle Test') { throw 'Unexpected installed identity.' }
  # Snapshot only the test identity, not the real user's Workspace/credentials.
  Save-Progress 'snapshot-before'
  & python.exe (Join-Path $Root 'snapshot_skilldeck_state.py') (Join-Path $output "$scenario-before.json") --root $dataRoot
  if ($LASTEXITCODE -ne 0) { throw 'Cannot snapshot isolated Workspace before update.' }
  $launched = @(Get-Process SkillDeck -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $appPath })
  $process = if ($launched.Count -eq 1) { $launched[0] } else {
    Start-Process -FilePath $appPath -WorkingDirectory $installRoot -PassThru
  }
  $result.oldProcessId = $process.Id
  Save-Progress 'waiting-native-dialog'
  $lastLabel = ''
  $clicks = 0
  $hiddenDone = $false
  for ($attempt=0; $attempt -lt 240; $attempt++) {
    Start-Sleep -Milliseconds 500
    if ($Hidden -and !$hiddenDone) {
      $main = [UpdateWin32]::FindWindow('FLUTTER_RUNNER_WIN32_WINDOW', 'SkillDeck')
      if ($main -ne [IntPtr]::Zero -and [UpdateWin32]::IsWindowVisible($main)) {
        [UpdateWin32]::PostMessage($main, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
        $hiddenDone = $true
      }
    }
    if ($process.HasExited) { break }
    $button = [UpdateWin32]::AcceptButton($process.Id)
    if ($null -eq $button -or $button.label -notmatch 'Download|Install|\u4e0b\u8f7d|\u5b89\u88c5') {
      # The same Install label returns after the disabled download phase.
      $lastLabel = ''
    }
    if ($attempt % 10 -eq 0) {
      $result.buttonLabel = if ($null -ne $button) { $button.label } else { '' }
      $result.acceptedButtons = $clicks
      $result.nativeDialogs = [UpdateWin32]::Describe($process.Id)
      Save-Progress 'waiting-native-dialog'
    }
    # Keep the script ASCII: Windows PowerShell 5 decodes BOM-less UTF-8 as ANSI.
    if ($null -ne $button -and $button.label -ne $lastLabel -and $button.label -match 'Download|Install|\u4e0b\u8f7d|\u5b89\u88c5') {
      $lastLabel = $button.label
      $clicks++
      [UpdateWin32]::Click($button.hwnd)
    }
  }
  $result.acceptedButtons = $clicks
  if (!$process.HasExited -or $clicks -eq 0) { throw 'Accepted native update did not end the old process.' }
  $result.oldProcessExited = $true
  $newProcess = $null
  for ($attempt=0; $attempt -lt 240; $attempt++) {
    Start-Sleep -Milliseconds 500
    $candidates = @(Get-Process SkillDeck -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $appPath })
    $version = (Get-Item -LiteralPath $appPath).VersionInfo.FileVersion
    if ($version -eq '0.0.2+2' -and $candidates.Count -eq 1) { $newProcess = $candidates[0]; break }
  }
  if ($null -eq $newProcess) { throw 'Installer did not replace and relaunch one N process.' }
  $result.newProcessId = $newProcess.Id
  $result.fileVersion = $version
  Start-Sleep -Seconds 3
  & python.exe (Join-Path $Root 'snapshot_skilldeck_state.py') (Join-Path $output "$scenario-after.json") --root $dataRoot
  if ($LASTEXITCODE -ne 0) { throw 'Cannot snapshot isolated Workspace after update.' }
  $before = Get-FileHash -LiteralPath (Join-Path $output "$scenario-before.json") -Algorithm SHA256
  $after = Get-FileHash -LiteralPath (Join-Path $output "$scenario-after.json") -Algorithm SHA256
  $result.userDataPreserved = $before.Hash -eq $after.Hash
  if (!$result.userDataPreserved) { throw 'Isolated user-data snapshot changed.' }
  $result.stage = 'complete'
  $result.status = 'passed'
} catch {
  $result.error = $_.Exception.Message
} finally {
  # Only the disposable identity is allowed here; leave the production App alone.
  foreach ($running in @(Get-Process SkillDeck -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $appPath })) {
    $main = [UpdateWin32]::FindWindow('FLUTTER_RUNNER_WIN32_WINDOW', 'SkillDeck')
    [UpdateWin32]::PostMessage($main, 0x0016, [IntPtr]1, [IntPtr]1) | Out-Null
    if (!$running.WaitForExit(5000)) { Stop-Process -Id $running.Id -Force }
  }
  $result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output "$scenario.result.json") -Encoding UTF8
}
if ($result.status -ne 'passed') { exit 1 }
