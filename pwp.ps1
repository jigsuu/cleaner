#region Admin Check
# Check if the script is running with Administrator privileges. If not, re-launch as admin.
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    # Re-launch the script with elevated privileges
    $arguments = "& '$($MyInvocation.MyCommand.Path)'"
    Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments
    # Exit the current, non-elevated script
    exit
}
#endregion Admin Check

#region Module Checks
# Check for necessary PowerShell modules and exit if they are not found.
$requiredModules = @("ScheduledTasks", "DnsClient")
foreach ($mod in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $mod)) {
        [System.Windows.Forms.MessageBox]::Show("Required module '$mod' is not available. Please run this script on a modern Windows system (Windows 10/11) or install the necessary components.", "Missing Requirement", "OK", "Error")
        exit 1
    }
}

# Explicitly import modules to ensure cmdlets are available.
try {
    Import-Module -Name "ScheduledTasks" -ErrorAction Stop
    Import-Module -Name "DnsClient" -ErrorAction Stop
} catch {
    [System.Windows.Forms.MessageBox]::Show("Failed to import a required module: $_. The script cannot continue.", "Import Error", "OK", "Error")
    exit 1
}
#endregion Module Checks

#region Password & License Checks
function Show-PasswordPrompt {
    # IMPORTANT: Set your desired password here.
    $correctPassword = "jigsuu3333"

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Password Required'
    $form.Size = New-Object System.Drawing.Size(320, 160)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'None' # Borderless to match main form
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    # Apply the same gradient background and border as the main form
    $form.Add_Paint({
        param($src, $evt)
        $graphics = $evt.Graphics
        $gradientRect = $src.ClientRectangle
        $gradientBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($gradientRect, $theme_backgroundStart, $theme_backgroundEnd, [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
        $graphics.FillRectangle($gradientBrush, $gradientRect)
        $borderPen = New-Object System.Drawing.Pen($theme_accent, 2)
        $borderPen.Alignment = [System.Drawing.Drawing2D.PenAlignment]::Inset
        $graphics.DrawRectangle($borderPen, $src.ClientRectangle)
        $gradientBrush.Dispose()
        $borderPen.Dispose()
    })

    $label = New-Object System.Windows.Forms.Label
    $label.Location = New-Object System.Drawing.Point(10, 20)
    $label.Size = New-Object System.Drawing.Size(280, 20)
    $label.Text = 'Please enter the password to continue:'
    $label.ForeColor = $theme_text
    $label.BackColor = [System.Drawing.Color]::Transparent
    $label.Font = $regularButtonFont
    $form.Controls.Add($label)

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Location = New-Object System.Drawing.Point(10, 50)
    $textBox.Size = New-Object System.Drawing.Size(280, 20)
    $textBox.PasswordChar = '*'
    $textBox.BackColor = $theme_button_hover
    $textBox.ForeColor = $theme_text
    $textBox.BorderStyle = 'FixedSingle'
    $form.Controls.Add($textBox)

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Location = New-Object System.Drawing.Point(110, 90)
    $okButton.Size = New-Object System.Drawing.Size(90, 30)
    $okButton.Text = 'OK'
    $okButton.Font = $boldButtonFont
    $okButton.BackColor = $theme_accent
    $okButton.ForeColor = $theme_text
    $okButton.FlatStyle = 'Flat'
    $okButton.FlatAppearance.BorderSize = 0
    $okButton.FlatAppearance.MouseOverBackColor = $theme_accent_hover
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton = $okButton
    $okButton.Region = [System.Drawing.Region]::FromHrgn([Win32]::CreateRoundRectRgn(0, 0, $okButton.Width, $okButton.Height, 15, 15))
    $form.Controls.Add($okButton)

    if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        if ($textBox.Text -ne $correctPassword) {
            [System.Windows.Forms.MessageBox]::Show("Incorrect password.", "Access Denied", "OK", "Error")
            exit
        }
    } else {
        # If the form is closed without clicking OK (which is disabled here, but good practice)
        exit
    }
}
#endregion Password & License Checks

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Add P/Invoke for rounded corners
$cSharpCode = @"
using System;
using System.Runtime.InteropServices;
using System.Drawing;
using System.Windows.Forms;
public class Win32 {
    [DllImport("Gdi32.dll", EntryPoint = "CreateRoundRectRgn")]
    public static extern IntPtr CreateRoundRectRgn
    (
        int nLeftRect,
        int nTopRect,
        int nRightRect,
        int nBottomRect,
        int nWidthEllipse,
        int nHeightEllipse
    );
}
"@
if (-not ([System.Management.Automation.PSTypeName]'Win32').Type) {
    Add-Type -TypeDefinition $cSharpCode -ReferencedAssemblies System.Drawing, System.Windows.Forms
}

# Add P/Invoke for Memory Scanning
$cSharpMemoryScannerCode = @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

public class MemoryScanner {
    // Process access flags
    const int PROCESS_QUERY_INFORMATION = 0x0400;
    const int PROCESS_VM_READ = 0x0010;

    // Memory state and type flags
    const uint MEM_COMMIT = 0x1000;
    const uint PAGE_READWRITE = 0x04;
    const uint PAGE_EXECUTE_READWRITE = 0x40;
    const uint PAGE_READONLY = 0x02;
    const uint PAGE_EXECUTE_READ = 0x20;

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr OpenProcess(int dwDesiredAccess, bool bInheritHandle, int dwProcessId);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool ReadProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress, byte[] lpBuffer, int dwSize, out int lpNumberOfBytesRead);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern int VirtualQueryEx(IntPtr hProcess, IntPtr lpAddress, out MEMORY_BASIC_INFORMATION lpBuffer, uint dwLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool CloseHandle(IntPtr hObject);

    [StructLayout(LayoutKind.Sequential)]
    public struct MEMORY_BASIC_INFORMATION {
        public IntPtr BaseAddress;
        public IntPtr AllocationBase;
        public uint AllocationProtect;
        public IntPtr RegionSize; // Use IntPtr for 64-bit compatibility
        public uint State;
        public uint Protect;
        public uint Type;
    }
}
"@
Add-Type -TypeDefinition $cSharpMemoryScannerCode

#region Helper Functions
function Show-Status ($message, $color = 'Default') {
    $themeColors = @{
        'Default' = [System.Drawing.Color]::White
        'Black'   = $theme_text # Remap black to white for text
        'Green'   = [System.Drawing.Color]::Lime # Bright Green
        'Red'     = [System.Drawing.Color]::Red # Bright Red
    }
    # Use the provided color if it's in the map, otherwise default to White
    $finalColor = if ($themeColors.ContainsKey($color)) { $themeColors[$color] } else { [System.Drawing.Color]::White }

    $statusBar.ForeColor = $finalColor
    $statusBar.Text = "Status: $message"
    $mainForm.Refresh()
}

function Show-CompletionDialog ($message) {
    # Use the built-in MessageBox for a simpler, smaller dialog.
    # It will show a standard Windows dialog with an 'OK' button and an information icon.
    [System.Windows.Forms.MessageBox]::Show($mainForm, $message, 'Operation Complete', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}

function Disable-Buttons {
    $allControls = @()
    $allControls += $mainForm.Controls
    $allControls += $page1Panel.Controls
    $allControls += $page2Panel.Controls
    $allControls += $page3Panel.Controls

    $allControls | Where-Object { $_ -is [System.Windows.Forms.Button] } | ForEach-Object { $_.Enabled = $false }
}

function Enable-Buttons {
    $allControls = @()
    $allControls += $mainForm.Controls
    $allControls += $page1Panel.Controls
    $allControls += $page2Panel.Controls
    $allControls += $page3Panel.Controls

    $allControls | Where-Object { $_ -is [System.Windows.Forms.Button] } | ForEach-Object { $_.Enabled = $true }
}

function Invoke-Command ($command, $arguments) {
    try {
        $process = Start-Process -FilePath $command -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
        if ($process.ExitCode -ne 0) {
            Show-Status "Error executing $command. Exit code: $($process.ExitCode)" "Red"
        }
    }
    catch {
        Show-Status "Failed to start process: $command. $_" "Red"
    }
}

function Invoke-CommandAsTrustedInstaller {
    param(
        [string]$CommandToRun
    )

    # Ensure the EventLog service is running, as the Task Scheduler depends on it.
    Start-Service -Name "EventLog" -ErrorAction SilentlyContinue

    # Ensure the Task Scheduler service is running, as it's required for this function.
    Start-Service -Name "Schedule" -ErrorAction SilentlyContinue

    $taskName = "OptiShitCleanerTask_$(Get-Random)"
    $tempScriptPath = Join-Path $env:TEMP "$(Get-Random).ps1"
    
    # Create a temporary script file for the scheduled task to execute
    Set-Content -Path $tempScriptPath -Value $CommandToRun

    $taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$tempScriptPath`""
    $taskPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

    try {
        Show-Status "Registering high-privilege task..."
        Register-ScheduledTask -TaskName $taskName -Action $taskAction -Principal $taskPrincipal -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries) -Force | Out-Null
        Show-Status "Executing task as SYSTEM..."
        Start-ScheduledTask -TaskName $taskName
        
        # Wait for the task to complete
        $task = Get-ScheduledTask -TaskName $taskName
        while ($task.State -ne 'Ready') {
            Start-Sleep -Seconds 1
            $task = Get-ScheduledTask -TaskName $taskName
        }
    }
    finally {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item -Path $tempScriptPath -Force -ErrorAction SilentlyContinue
    }
}

function New-RoundedRectPath {
    param($rect, $cornerRadius)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc($rect.X, $rect.Y, $cornerRadius, $cornerRadius, 180, 90)
    $path.AddArc($rect.Right - $cornerRadius, $rect.Y, $cornerRadius, $cornerRadius, 270, 90)
    $path.AddArc($rect.Right - $cornerRadius, $rect.Bottom - $cornerRadius, $cornerRadius, $cornerRadius, 0, 90)
    $path.AddArc($rect.X, $rect.Bottom - $cornerRadius, $cornerRadius, $cornerRadius, 90, 90)
    $path.CloseFigure()
    return $path
}

function Update-PageVisibility {
    $page1Panel.Visible = ($script:currentPage -eq 1)
    $page2Panel.Visible = ($script:currentPage -eq 2)
    $page3Panel.Visible = ($script:currentPage -eq 3)

    $prevButton.Visible = ($script:currentPage -gt 1)
    $nextButton.Visible = ($script:currentPage -lt $script:totalPages)
}

#endregion Helper Functions

#region "Apply All" Function
function Remove-All {
    # --- Progress Bar Setup ---
    $progressBar.Visible = $true
    $progressBar.Value = 0
    $progressBar.Maximum = 37 # Total number of steps in the Remove-All process
    
    Disable-Buttons
    Show-Status "Phase 0: Disabling Telemetry & Logging..."
    Disable-TelemetryDeep -IsPartOfBatch
    $progressBar.PerformStep()

    Show-Status "Starting comprehensive cleaning..."

    # Phase 1: Stop Processes & Clean Application/Game Data

    Show-Status "Phase 1: Cleaning Apps & Games..."
    Remove-BrowserMemoryStrings -IsPartOfBatch # Stops browsers
    $progressBar.PerformStep()
    Remove-BrowsingData -IsPartOfBatch
    $progressBar.PerformStep()
    Remove-FiveMTraces -IsPartOfBatch # Stops game launchers
    $progressBar.PerformStep()
    Remove-SteamAccounts -IsPartOfBatch 
    $progressBar.PerformStep()
    Remove-EpicGames -IsPartOfBatch 
    $progressBar.PerformStep()
    Remove-RockstarCache -IsPartOfBatch 
    $progressBar.PerformStep()
    Remove-DiscordCache -IsPartOfBatch 
    $progressBar.PerformStep()

    # Phase 2: System File & OS Cache Cleanup
    Show-Status "Phase 2: Cleaning System Files & Caches..."
    Remove-TempFiles -IsPartOfBatch
    $progressBar.PerformStep()
    Remove-CpuCaches -IsPartOfBatch
    $progressBar.PerformStep()
    Remove-PrintSpooler -IsPartOfBatch 
    $progressBar.PerformStep()
    Remove-ImGuiIniFiles -IsPartOfBatch 
    $progressBar.PerformStep()
    Remove-Shadows -IsPartOfBatch 
    $progressBar.PerformStep()
    Remove-WmiRepository -IsPartOfBatch 
    $progressBar.PerformStep()

    # Phase 3: Driver & Hardware-Related Caches
    Show-Status "Phase 3: Cleaning Driver & Hardware Caches..."
    Remove-NvidiaCache -IsPartOfBatch
    $progressBar.PerformStep()
    Remove-AmdCache -IsPartOfBatch 
    $progressBar.PerformStep()
    Remove-DirectXCache -IsPartOfBatch 
    $progressBar.PerformStep()

    # Phase 4: Registry, History & Forensic Traces
    Show-Status "Phase 4: Cleaning Registry & History..."
    Remove-FormHistory -IsPartOfBatch
    $progressBar.PerformStep()
    Invoke-ForensicBypass -IsPartOfBatch # This is the most aggressive function
    $progressBar.PerformStep()
    Invoke-AntiForensics -IsPartOfBatch
    $progressBar.PerformStep()
    Remove-NirSoftTraces -IsPartOfBatch
    $progressBar.PerformStep()
    Remove-OSForensicsLogs -IsPartOfBatch
    $progressBar.PerformStep()
    Remove-XboxDeep -IsPartOfBatch
    $progressBar.PerformStep()
    Remove-DefenderHistory -IsPartOfBatch
    $progressBar.PerformStep()

    # Phase 5: Network, Memory & Power
    Show-Status "Phase 5: Optimizing Network, Memory & Power..."
    Remove-BitsJobs -IsPartOfBatch
    $progressBar.PerformStep()
    Reset-DataUsage -IsPartOfBatch
    $progressBar.PerformStep()
    Clear-DnsCache -IsPartOfBatch
    $progressBar.PerformStep()
    Flush-StandbyCache -IsPartOfBatch
    $progressBar.PerformStep()
    Remove-BamDamLogs -IsPartOfBatch
    $progressBar.PerformStep()
    Optimize-PowerAndSleep -IsPartOfBatch
    $progressBar.PerformStep()

    # Phase 6: Finalizing and Self-Cleaning
    Show-Status "Phase 6: Finalizing..."
    Remove-RecentApps -IsPartOfBatch
    $progressBar.PerformStep()
    Remove-RunHistoryDeep -IsPartOfBatch
    $progressBar.PerformStep()
    Remove-UsnJournal -IsPartOfBatch
    $progressBar.PerformStep()
    Remove-PowershellHistory -IsPartOfBatch 
    $progressBar.PerformStep()
    Clear-EventLogs -IsPartOfBatch # Clear all event logs as the final step
    $progressBar.PerformStep()

    Show-Status "Phase 7: Re-enabling system logging..."
    # This is important to re-enable core services like EventLog for normal operation.
    Enable-AllLogging -IsPartOfBatch 
    $progressBar.PerformStep()
    
    $completionMessage = "cleaning complete."
    Show-Status $completionMessage "Green"
    Show-CompletionDialog $completionMessage
    $progressBar.Visible = $false
    Enable-Buttons
}
#endregion

#region Forensic Bypass Function
function Invoke-ForensicBypass {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Attempting forensic bypass... This is extremely high-risk." "Red"

    # --- Phase 1: Service & Process Manipulation ---
    Show-Status "Phase 1: Terminating forensic tools and disabling logging..."

    # Terminate common forensic and analysis tools
    $forensicTools = @(
        "FTKImager", "x64_imager", "x86_imager", "xways", "winhex", "procexp", "procexp64", "procexp64a",
        "procmon", "autoruns", "tcpview", "volatility", "dumpit", "regshot", "wireshark", "handle",
        "strings", "apimonitor", "ollydbg", "windbg", "idaq", "idaq64", "cheatengine-x86_64"
    )
    $forensicTools | ForEach-Object { Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue }

    # --- Phase 1b: Disable Logging Services ---
    # Stop Sysmon if it's running, a very common forensic logging tool.
    $sysmonCommand = "Stop-Service -Name Sysmon -Force; Stop-Service -Name Sysmon64 -Force"
    Invoke-CommandAsTrustedInstaller -CommandToRun $sysmonCommand

    # Temporarily disable the main EventLog service. This is the most aggressive logging stop.
    $command = "Stop-Service -Name EventLog -Force; Set-Service -Name EventLog -StartupType Disabled"
    Invoke-CommandAsTrustedInstaller -CommandToRun $command
    Start-Sleep -Seconds 2 # Give it a moment

    # --- Phase 2: Deleting High-Value Forensic Artifacts ---
    Show-Status "Phase 2: Deleting high-value forensic artifacts..."

    # Directly target some of the most valuable forensic files.
    $directArtifacts = @(
        "$env:SystemRoot\inf\setupapi.dev.log", # Logs all PnP device installations
        "$env:SystemRoot\System32\sru\srudb.dat" # System Resource Usage Monitor DB
    )
    foreach ($artifact in $directArtifacts) {
        Invoke-CommandAsTrustedInstaller -CommandToRun "Remove-Item -Path '$artifact' -Force -ErrorAction SilentlyContinue"
    }

    # Clear network device history
    Invoke-Command "arp" "-d *"
    Invoke-Command "nbtstat" "-R"

    # These functions are already aggressive and target key areas.
    Remove-UsnJournal -IsPartOfBatch
    Remove-Shadows -IsPartOfBatch
    Remove-Amcache -IsPartOfBatch
    Remove-ShimCache -IsPartOfBatch
    Remove-AllUsbHistory -IsPartOfBatch
    Clear-RegistryTracking -IsPartOfBatch
    Reset-DataUsage -IsPartOfBatch # This clears SRUM DB

    # --- Phase 3: Aggressive Registry & File System Cleaning ---
    Show-Status "Phase 3: Aggressive registry and event log cleaning..."
    Remove-RegistryTraces # This is a standalone function, call it directly

    # --- Phase 4: Finalization ---
    Show-Status "Phase 4: Re-enabling services and finalizing..."

    # Re-enable the EventLog service
    $command = "Set-Service -Name EventLog -StartupType Automatic; Start-Service -Name EventLog"
    Invoke-CommandAsTrustedInstaller -CommandToRun $command

    if (-not $IsPartOfBatch) {
        $completionMessage = "Forensic bypass sequence completed. A system restart is highly recommended."
        Show-Status $completionMessage "Green"
        Show-CompletionDialog $completionMessage
        Enable-Buttons
    }
}
#endregion

#region Anti-Forensics Function
function Invoke-AntiForensics {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Running advanced anti-forensics cleanup..."

    # This command block will be executed as the SYSTEM user for maximum permissions.
    $command = @"
`$ErrorActionPreference = 'SilentlyContinue'

# 1. Disable and Stop Telemetry Services
Show-Status "Disabling telemetry services..."
Set-Service -Name 'DiagTrack' -StartupType Disabled
Stop-Service -Name 'DiagTrack' -Force
Set-Service -Name 'dmwappushservice' -StartupType Disabled
Stop-Service -Name 'dmwappushservice' -Force

# 2. Clear Scheduled Task History
Show-Status "Clearing scheduled task history..."
Remove-Item -Path "`$env:SystemRoot\System32\winevt\Logs\Microsoft-Windows-TaskScheduler%4Operational.evtx" -Force

# 3. Clear Windows Update Logs
Show-Status "Clearing Windows Update logs..."
Remove-Item -Path "`$env:SystemRoot\SoftwareDistribution\ReportingEvents.log" -Force

# 4. Find and delete any PowerShell transcript logs system-wide
Show-Status "Searching for and deleting PowerShell transcripts..."
Get-ChildItem -Path "`$env:SystemDrive\" -Recurse -Filter "PowerShell_transcript.*.txt" -File -ErrorAction SilentlyContinue | Remove-Item -Force
"@
    Invoke-CommandAsTrustedInstaller -CommandToRun $command

    if (-not $IsPartOfBatch) {
        $completionMessage = "Advanced anti-forensics cleanup complete."
        Show-Status $completionMessage "Green"; Show-CompletionDialog $completionMessage; Enable-Buttons
    }
}
#endregion

#region Logging Control Functions
function Disable-AllLogging {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Disabling system-wide logging services..."

    # This command block will be executed as the SYSTEM user for maximum permissions.
    $command = @"
`$ErrorActionPreference = 'SilentlyContinue'

# 1. Disable and Stop Telemetry & Diagnostic Services
Set-Service -Name 'DiagTrack' -StartupType Disabled; Stop-Service -Name 'DiagTrack' -Force
Set-Service -Name 'dmwappushservice' -StartupType Disabled; Stop-Service -Name 'dmwappushservice' -Force

# 2. Disable PowerShell Event Logging
wevtutil.exe sl "Microsoft-Windows-PowerShell/Operational" /e:false /q:true

# 3. Disable Registry Access Auditing
auditpol /set /subcategory:`"Registry`" /success:disable /failure:disable

# 4. Stop the main EventLog service (most aggressive step)
Stop-Service -Name EventLog -Force
Set-Service -Name EventLog -StartupType Disabled
"@
    Invoke-CommandAsTrustedInstaller -CommandToRun $command

    if (-not $IsPartOfBatch) {
        $completionMessage = "System-wide logging disabled."
        Show-Status $completionMessage "Green"; Show-CompletionDialog $completionMessage; Enable-Buttons
    }
}

function Enable-AllLogging {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Re-enabling system-wide logging services..."

    $command = @"
`$ErrorActionPreference = 'SilentlyContinue'

# 1. Re-enable the main EventLog service
Set-Service -Name EventLog -StartupType Automatic; Start-Service -Name EventLog

# 2. Re-enable PowerShell Event Logging
wevtutil.exe sl "Microsoft-Windows-PowerShell/Operational" /e:true /q:true

# 3. Re-enable Telemetry & Diagnostic Services (restoring to default)
Set-Service -Name 'DiagTrack' -StartupType Automatic; Start-Service -Name 'DiagTrack'
Set-Service -Name 'dmwappushservice' -StartupType Automatic; Start-Service -Name 'dmwappushservice'
"@
    Invoke-CommandAsTrustedInstaller -CommandToRun $command

    if (-not $IsPartOfBatch) { $completionMessage = "System-wide logging re-enabled."; Show-Status $completionMessage "Green"; Show-CompletionDialog $completionMessage; Enable-Buttons }
}
#endregion

#region Disable Telemetry Deep Function
function Disable-TelemetryDeep {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Performing deep telemetry disable (requires SYSTEM)..." "Red"

    $command = @"
`$ErrorActionPreference = 'SilentlyContinue'

# 1. Disable and Stop a wide range of Telemetry & Data Collection services
Write-Host "Disabling Telemetry and Data Collection services..."
`$services = @(
    "DiagTrack",                  # Connected User Experiences and Telemetry
    "dmwappushservice",           # WAP Push Message Routing Service
    "diagnosticshub.standardcollector.service", # Microsoft Diagnostics Hub Standard Collector
    "WdiServiceHost",             # Diagnostic Service Host
    "WdiSystemHost"               # Diagnostic System Host
)
foreach (`$service in `$services) {
    Set-Service -Name `$service -StartupType Disabled -ErrorAction SilentlyContinue
    Stop-Service -Name `$service -Force -ErrorAction SilentlyContinue
}

# 2. Delete Telemetry-related Scheduled Tasks
Write-Host "Deleting Telemetry-related Scheduled Tasks..."
`$tasks = @(
    "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
    "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
    "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
    "\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask",
    "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
    "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector"
)
foreach (`$task in `$tasks) {
    Unregister-ScheduledTask -TaskPath `$task -Confirm:`$false -ErrorAction SilentlyContinue
}

# 3. Apply numerous registry tweaks to disable telemetry
Write-Host "Applying registry tweaks to disable telemetry..."
`$regTweaks = @{
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" = @{ "AllowTelemetry" = 0 }
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" = @{ "AllowTelemetry" = 0 }
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat" = @{ "AITelemetryEnabled" = 0; "DisableInventory" = 1 }
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" = @{ "DisableWindowsConsumerFeatures" = 1 }
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" = @{ "Disabled" = 1 }
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" = @{ "DODownloadMode" = 0 }
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" = @{ "Enabled" = 0 }
    "HKCU:\Software\Microsoft\Input\TIPC" = @{ "Enabled" = 0 }
}

foreach (`$key in `$regTweaks.Keys) {
    if (-not (Test-Path `$key)) { New-Item -Path `$key -Force | Out-Null }
    Set-ItemProperty -Path `$key -Name (`$regTweaks[`$key].Keys) -Value (`$regTweaks[`$key].Values) -Force
}
"@
    Invoke-CommandAsTrustedInstaller -CommandToRun $command

    if (-not $IsPartOfBatch) {
        $completionMessage = "Deep telemetry disable complete. A restart is recommended."
        Show-Status $completionMessage "Green"; Show-CompletionDialog $completionMessage; Enable-Buttons
    }
}
#endregion

#region Memory String Collection Function
function Get-FiveMCheatStrings {
    Disable-Buttons
    Show-Status "Collecting memory strings... This is high-risk." "Red"

    $result = [System.Windows.Forms.MessageBox]::Show(
        "This function will scan the memory of critical system processes for specific strings. This is a high-risk operation. Do you want to continue?", 
        "Confirm High-Risk Operation", 
        [System.Windows.Forms.MessageBoxButtons]::YesNo, 
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($result -ne 'Yes') {
        Show-Status "Memory scan cancelled by user."
        Enable-Buttons
        return
    }

    # Define target processes and cheat strings
    $targetProcesses = @("csrss", "lsass", "dps", "explorer")
    # Add PcaSvc by finding its host process
    try {
        $pcaSvc = Get-CimInstance -ClassName Win32_Service -Filter "Name='PcaSvc'" | Select-Object -ExpandProperty ProcessId
        if ($pcaSvc) {
            $pcaProcName = (Get-Process -Id $pcaSvc -ErrorAction SilentlyContinue).ProcessName
            if ($pcaProcName -and $targetProcesses -notcontains $pcaProcName) {
                $targetProcesses += $pcaProcName
            }
        }
    } catch {}

    # Placeholder for cheat-related strings. Replace with actual strings.
    $cheatStrings = @(
        "imgui.exe",
        "imgui"
    )

    $foundStringsLog = @()

    foreach ($procName in $targetProcesses) {
        $processes = Get-Process -Name $procName -ErrorAction SilentlyContinue
        if (-not $processes) {
            Show-Status "Process '$procName' not found. Skipping."
            Start-Sleep -Seconds 1
            continue
        }

        foreach ($process in $processes) {
            Show-Status "Scanning process: $($process.ProcessName) (PID: $($process.Id))..."
            $processHandle = [MemoryScanner]::OpenProcess(0x0410, $false, $process.Id) # PROCESS_QUERY_INFORMATION | PROCESS_VM_READ

            if ($processHandle -eq [IntPtr]::Zero) {
                Show-Status "Could not open process $($process.ProcessName) (PID: $($process.Id)). Skipping." "Red"
                Start-Sleep -Seconds 1
                continue
            }

            $memInfo = New-Object MemoryScanner+MEMORY_BASIC_INFORMATION
            $currentAddr = [IntPtr]::Zero
            $maxAddress = if ([IntPtr]::Size -eq 8) { [IntPtr]0x7FFFFFFFFFF } else { [IntPtr]0x7FFFFFFF }

            while ($currentAddr.ToInt64() -lt $maxAddress.ToInt64()) {
                $result = [MemoryScanner]::VirtualQueryEx($processHandle, $currentAddr, [ref]$memInfo, [System.Runtime.InteropServices.Marshal]::SizeOf($memInfo))
                if ($result -eq 0) { break }

                if ($memInfo.State -eq 0x1000) { # MEM_COMMIT
                    $regionSize = $memInfo.RegionSize.ToInt64()
                    $buffer = New-Object byte[]($regionSize)
                    $bytesRead = 0

                    if ([MemoryScanner]::ReadProcessMemory($processHandle, $memInfo.BaseAddress, $buffer, $buffer.Length, [ref]$bytesRead)) {
                        $regionContent = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $bytesRead)
                        foreach ($str in $cheatStrings) {
                            if ($regionContent.IndexOf($str, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                                $logEntry = "Found '$str' in $($process.ProcessName) (PID: $($process.Id)) at approx address $($memInfo.BaseAddress)"
                                Show-Status $logEntry "Red"
                                $foundStringsLog += $logEntry
                            }
                        }
                    }
                }
                $currentAddr = [IntPtr]($memInfo.BaseAddress.ToInt64() + $memInfo.RegionSize.ToInt64())
            }
            [MemoryScanner]::CloseHandle($processHandle)
        }
    }

    if ($foundStringsLog.Count -gt 0) {
        $logPath = Join-Path $env:TEMP "cheat_scan_log.txt"
        $foundStringsLog | Out-File -FilePath $logPath -Append
        $completionMessage = "Memory scan complete. Found potential cheat strings. See log: $logPath"
        Show-CompletionDialog $completionMessage
    } else {
        $completionMessage = "Memory scan complete. No specified strings found."
        Show-CompletionDialog $completionMessage
    }

    Show-Status $completionMessage "Green"
    Enable-Buttons
}
#endregion

#region Cleaning Functions

function Clear-DnsCache {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Clearing DNS Cache..."
    
    Invoke-Command "netsh" "interface ip delete arpcache"
    Invoke-Command "ipconfig" "/flushdns"
    
    Show-Status "Temporarily disabling EventLog service (requires SYSTEM)..."
    $command = "Stop-Service -Name EventLog -Force; Set-Service -Name EventLog -StartupType Disabled"
    Invoke-CommandAsTrustedInstaller -CommandToRun $command

    Show-Status "Restarting DNS Client service..."
    Restart-Service -Name "dnscache" -Force -ErrorAction SilentlyContinue
    
    Show-Status "Releasing and renewing IP address..."
    Invoke-Command "ipconfig" "/release"
    Start-Sleep -Seconds 3
    Invoke-Command "ipconfig" "/renew"
    
    Show-Status "Resetting network components..."
    Invoke-Command "netsh" "winsock reset"
    Invoke-Command "netsh" "advfirewall reset"
    Invoke-Command "netsh" "int ip reset"
    
    Clear-DnsClientCache
    Invoke-Command "arp" "-d *"
    Invoke-Command "nbtstat" "-R"
    
    if (-not $IsPartOfBatch) {
        $completionMessage = "DNS Cache cleared successfully."
        Show-Status $completionMessage "Green"
        Show-CompletionDialog $completionMessage
        Enable-Buttons
    }
}

function Remove-FiveMTraces {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Cleaning FiveM Traces..."

    $processes = @(
        "GTAVLauncher", "FiveM", "FiveM_GTAProcess", "FiveM_b2612_GTAProcess",
        "FiveM_b2372_GTAProcess", "FiveM_b3095_GTAProcess", "steam", "Discord",
        "DiscordPTB", "DiscordCanary", "EpicGamesLauncher", "RockstarGamesLauncher",
        "RockstarService", "EpicGamesLauncher.exe", "EasyAntiCheat.exe", "Origin",
        "EADesktop", "Battle.net", "RiotClientServices"
    )
    $processes | ForEach-Object { Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue }

    $foldersToDelete = @(
        "$env:USERPROFILE\AppData\Local\Steam\htmlcache",
        "$env:USERPROFILE\AppData\Local\EpicGamesLauncher\Saved\webcache",
        "$env:USERPROFILE\AppData\Local\FiveM\FiveM.app\data\cache",
        "$env:USERPROFILE\AppData\Local\DigitalEntitlements",
        "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\Recent\CustomDestinations",
        "$env:LOCALAPPDATA\Steam\htmlcache\Network",
        "$env:LOCALAPPDATA\Steam\htmlcache\Cache\Cache_Data",
        "$env:LOCALAPPDATA\Packages\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\AppData\CacheStorage",
        "$env:LOCALAPPDATA\FiveM\FiveM.app\cache", # Parent cache folder
        "$env:APPDATA\CitizenFX"
    )

    $filesToDelete = @(
        "$env:LOCALAPPDATA\FiveM\FiveM.app\crashes\*.*",
        "$env:LOCALAPPDATA\FiveM\FiveM.app\logs\*.*",
        "$env:LOCALAPPDATA\FiveM\FiveM.app\discord.dll",
        "$env:LOCALAPPDATA\FiveM\FiveM.app\CitizenFX_SubProcess_chrome.bin",
        "$env:LOCALAPPDATA\FiveM\FiveM.app\CitizenFX_SubProcess_game.bin",
        "$env:LOCALAPPDATA\FiveM\FiveM.app\CitizenFX_SubProcess_game_*.bin",
        "$env:LOCALAPPDATA\FiveM\FiveM.app\botan.dll",
        "$env:LOCALAPPDATA\FiveM\FiveM.app\asi-five.dll",
        "$env:LOCALAPPDATA\FiveM\FiveM.app\steam.dll",
        "$env:LOCALAPPDATA\FiveM\FiveM.app\steam_api64.dll",
        "$env:LOCALAPPDATA\FiveM\FiveM.app\CitizenGame.dll",
        "$env:LOCALAPPDATA\FiveM\FiveM.app\profiles.dll",
        "$env:LOCALAPPDATA\FiveM\FiveM.app\cfx_curl_x86_64.dll",
        "$env:LOCALAPPDATA\FiveM\FiveM.app\CitizenFX.ini",
        "$env:LOCALAPPDATA\FiveM\FiveM.app\caches.XML",
        "$env:LOCALAPPDATA\FiveM\FiveM.app\adhesive.dll"
    )

    $foldersToDelete | ForEach-Object {
        if (Test-Path $_) {
            Show-Status "Removing folder: $_"
            Remove-Item -Path $_ -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $filesToDelete | ForEach-Object {
        if (Test-Path $_) {
            Show-Status "Removing file(s): $_"
            Remove-Item -Path $_ -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not $IsPartOfBatch) {
        $completionMessage = "FiveM trace cleaning complete."
        Show-Status $completionMessage "Green"
        Show-CompletionDialog $completionMessage
        Enable-Buttons
    }
}

function Remove-RegistryTraces {
    Disable-Buttons
    Show-Status "Cleaning registry traces... This is high-risk."
    
    $command = @"
    # This entire block will run as SYSTEM to bypass permissions issues.
    `$ErrorActionPreference = 'SilentlyContinue'

    `$currentUserSid = (Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty UserName).Split('\')[1]
    `$userSidObj = New-Object System.Security.Principal.NTAccount(`$currentUserSid)
    `$currentUserSid = `$userSidObj.Translate([System.Security.Principal.SecurityIdentifier]).Value

    `$hardcodedSid = 'S-1-5-21-2532382528-581214834-2534474248-1001'

    # This list contains templates. The hardcoded SID will be replaced by the current user's SID.
    # WARNING: The original script contained a massive, hardcoded list of registry keys.
    `$regKeys = @(
        "HKCR\Installer\Products",
        "HKCU\Software\7-Zip\FM\FileHistory",
        "HKCU\Software\7-Zip\FM\FolderHistory",
        "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU",
        "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU\*",
        "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags",
        "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache",
        "HKCU\Software\Classes\LocalSettings\MrtCache",
        "HKCU\Software\Microsoft\DirectInput",
        "HKCU\Software\Microsoft\InputPersonalization",
        "HKCU\Software\Microsoft\InputPersonalization\TrainedData",
        "HKCU\Software\Microsoft\Internet Explorer\TypedURLs",
        "HKCU\Software\Microsoft\Speech_OneCore\Settings\WordHarvester",
        "HKCU\Software\Microsoft\Terminal Server Client",
        "HKCU\Software\Microsoft\Terminal Server Client\Default",
        "HKCU\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Persisted",
        "HKCU\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store",
        "HKCU\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\ActivityCache\Activities",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\ApplicationFrame\Positions",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Applets\Regedit\Favorites",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Applets\Regedit\LastKey",
        "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Applets\Wordpad\Recent File List",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\Start_TrackDocs",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\Start_TrackProgs",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\CLSID",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\*",
        "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\CIDSizeMRU",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\FirstFolder",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\LastVisitedPidlMRU",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\LastVisitedPidlMRULegacy",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\OpenSavePidlMRU",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FeatureUsage\AppLaunch",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FeatureUsage\AppSwitched",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FeatureUsage\ShowJumpView",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\MenuOrder",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\MountPoints2",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs\",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartPage",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StreamMRU",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Streams",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\TrayNotify",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\WordWheelQuery",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Group Policy\History",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings\5.0\Cache",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Connections",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Privacy",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\PushNotifications",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Search\RecentApps",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
        "HKCU\Software\Microsoft\Windows\DWM",
        "HKCU\Software\Microsoft\Windows\Windows Error Reporting",
        "HKCU\Software\WinRAR\ArcHistory",
        "HKCU\Software\WinRAR\DialogEditHistory\ArcName",
        "HKCU\Software\WinRAR\DialogEditHistory\ExtrPath",
        "HKCU\Software\WinRAR\DialogEditHistory\UnpPath",
        "HKLM\SOFTWARE\Classes\LocalSettings\Software\Microsoft\Windows\CurrentVersion\AppModel\PackageRepository\Extensions\ProgIDs\AppXm8fs0gj5h36ynw4kq0x3gqnz6ecr1kvy",
        "HKLM\SOFTWARE\Classes\LocalSettings\Software\Microsoft\Windows\CurrentVersion\AppModel\PackageRepository\Extensions\windows.protocol\ms-gamebarservices\AppXm8fs0gj5h36ynw4kq0x3gqnz6ecr1kvy",
        "HKLM\SOFTWARE\Classes\LocalSettings\Software\Microsoft\Windows\CurrentVersion\AppModel\PackageRepository\Packages\Microsoft.XboxGameOverlay_1.41.24001.0_neutral_split.scale-100_8wekyb3d8bbwe",
        "HKLM\SOFTWARE\Classes\LocalSettings\Software\Microsoft\Windows\CurrentVersion\AppModel\PackageRepository\Packages\Microsoft.XboxGameOverlay_1.41.24001.0_neutral_~_8wekyb3d8bbwe",
        "HKLM\SOFTWARE\Classes\LocalSettings\Software\Microsoft\Windows\CurrentVersion\AppModel\PackageRepository\Packages\Microsoft.XboxGameOverlay_1.41.24001.0_x64__8wekyb3d8bbwe",
        "HKLM\SOFTWARE\Microsoft\MSLicensing\Store",
        "HKLM\SOFTWARE\Microsoft\RADAR\HeapLeakDetection\DiagnosedApplications",
        "HKLM\SOFTWARE\Microsoft\RADAR\HeapLeakDetection\DiagnosedApplications\FortniteClient-Win64-Shipping.exe",
        "HKLM\SOFTWARE\Microsoft\SecurityManager\CapAuthz\ApplicationsEx\Microsoft.XboxGameOverlay_1.41.24001.0_x64__8wekyb3d8bbwe",
        "HKLM\SOFTWARE\Microsoft\Tracing",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\Origins",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\Application\Data\93",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\Application\Index\Package\181",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\Application\Index\PackageAndPackageRelativeApplicationId\181^App",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\ApplicationUser\Data\ac",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\ApplicationUser\Data\ad",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\UserAndApplication\3^93",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\UserAndApplication\4^93",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\Package\Data\180",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\Package\Data\181",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\Package\Data\182",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\Package\Index\PackageFamily\4e",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\Package\Index\PackageFullName\Microsoft.XboxGameOverlay_1.41.24001.0_neutral_split.scale-100_8wekyb3d8bbwe",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\Package\Index\PackageFullName\Microsoft.XboxGameOverlay_1.41.24001.0_neutral_~_8wekyb3d8bbwe",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\Package\Index\PackageFullName\Microsoft.XboxGameOverlay_1.41.24001.0_x64__8wekyb3d8bbwe",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\PackageUser\Data\1a80",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\PackageUser\Data\1a81",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\PackageUser\Data\1a82",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\PackageUser\Data\1a83",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\PackageUser\Data\1a84",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\PackageUser\Index\User\3",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\PackageUser\Index\User\4",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\PackageUser\Index\UserAndPackage\3^180",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\PackageUser\Index\UserAndPackage\3^181",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\PackageUser\Index\UserAndPackage\3^182",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\PackageUser\Index\UserAndPackage\4^180",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\PackageUser\Index\UserAndPackage\4^181",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\PackageUser\Index\UserAndPackage\4^182",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Applications\Microsoft.XboxGameOverlay_1.41.24001.0_neutral_~_8wekyb3d8bbwe",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\S-1-5-21-2532382528-581214834-2534474248-1001\Microsoft.XboxGameOverlay_1.41.24001.0_neutral_~_8wekyb3d8bbwe",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting",
        "HKLM\SOFTWARE\Microsoft\WindowsNT\CurrentVersion\VolatileNotifications",
        "HKLM\SOFTWARE\WOW6432Node\Google\Update\UsageStats\Daily\Counts",
        "HKLM\SOFTWARE\WOW6432Node\Microsoft\SecurityManager\CapAuthz\ApplicationsEx\Microsoft.XboxGameOverlay_1.41.24001.0_x64__8wekyb3d8bbwe",
        "HKLM\SYSTEM\CurrentControlSet\Control\hivelist",
        "HKLM\SYSTEM\CurrentControlSet\Control\Print\Printers",
        "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Shares",
        "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Shares",
        "HKU\.DEFAULT\Software\Microsoft\SystemCertificates\TrustedPublisher",
        "HKU\.DEFAULT\Software\Microsoft\SystemCertificates\TrustedPublisher\Certificates",
        "HKU\.DEFAULT\Software\Microsoft\SystemCertificates\TrustedPublisher\CRLs",
        "HKU\.DEFAULT\Software\Microsoft\SystemCertificates\TrustedPublisher\CTLs",
        "HKU\.DEFAULT\Software\Policies\Microsoft\SystemCertificates\TrustedPublisher",
        "HKU\.DEFAULT\Software\Policies\Microsoft\SystemCertificates\TrustedPublisher\Certificates",
        "HKU\.DEFAULT\Software\Policies\Microsoft\SystemCertificates\TrustedPublisher\CRLs",
        "HKU\.DEFAULT\Software\Policies\Microsoft\SystemCertificates\TrustedPublisher\CTLs",
        "HKU\S-1-5-18\Software\Microsoft\SystemCertificates\TrustedPublisher",
        "HKU\S-1-5-18\Software\Microsoft\SystemCertificates\TrustedPublisher\Certificates",
        "HKU\S-1-5-18\Software\Microsoft\SystemCertificates\TrustedPublisher\CRLs",
        "HKU\S-1-5-18\Software\Microsoft\SystemCertificates\TrustedPublisher\CTLs",
        "HKU\S-1-5-18\Software\Policies\Microsoft\SystemCertificates\TrustedPublisher",
        "HKU\S-1-5-18\Software\Policies\Microsoft\SystemCertificates\TrustedPublisher\Certificates",
        "HKU\S-1-5-18\Software\Policies\Microsoft\SystemCertificates\TrustedPublisher\CRLs",
        "HKU\S-1-5-18\Software\Policies\Microsoft\SystemCertificates\TrustedPublisher\CTLs",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Classes\LocalSettings\MrtCache",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\InternetExplorer\LowRegistry\Audio\PolicyConfig\PropertyStore\5e4eddc4_0",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\ApplicationViewManagement\W32:0000000000020552",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\ApplicationViewManagement\W32:00000000000205B6",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\ApplicationViewManagement\W32:00000000000403D6",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\ApplicationViewManagement\W32:00000000000405DE",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\ApplicationViewManagement\W32:0000000000060286",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\ApplicationViewManagement\W32:00000000000703C4",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\ApplicationViewManagement\W32:000000000009042E",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\ApplicationViewManagement\W32:00000000000A03B4",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\ApplicationViewManagement\W32:00000000000A0430",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\ApplicationViewManagement\W32:00000000000B0532",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\ApplicationViewManagement\W32:00000000000B05D6",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\ApplicationViewManagement\W32:00000000000C0430",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\ApplicationViewManagement\W32:00000000000C0586",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\ApplicationViewManagement\W32:00000000000E03D2",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\ApplicationViewManagement\W32:00000000000E0406",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\ApplicationViewManagement\W32:0000000000100430",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\ApplicationViewManagement\W32:00000000001103EE",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\ApplicationViewManagement\W32:000000000011041E",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\ApplicationViewManagement\W32:000000000012047E",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\ApplicationViewManagement\W32:00000000001303EE",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\ApplicationViewManagement\W32:00000000001304F2",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\ApplicationViewManagement\W32:000000000014041E",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\ApplicationViewManagement\W32:00000000001703E6",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\ApplicationViewManagement\W32:0000000000170440",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\ApplicationViewManagement\W32:00000000001704FC",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\VirtualDesktops",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\Windows\CurrentVersion\Explorer\StreamMRU",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\Windows\CurrentVersion\Explorer\Streams\0",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist{CEBFF5CD-ACE2-4F4F-9178-9926F41749EA}\Count",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\Software\Microsoft\Windows\CurrentVersion\Search\JumplistData",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\System\GameConfigStore\Children\03ce6902-ff58-41de-ab92-36fcaf27a580",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001\System\GameConfigStore\Parents\fd13f746e7d2d69760b017363f621255c9b49ac8",
        "HKU\S-1-5-21-2532382528-581214834-2534474248-1001_Classes\LocalSettings\MrtCache",
        "HKU\S-1-5-18\Software\Microsoft\SystemCertificates\TrustedPublisher",
        "HKU\S-1-5-18\Software\Microsoft\SystemCertificates\TrustedPublisher\Certificates",
        "HKU\S-1-5-18\Software\Microsoft\SystemCertificates\TrustedPublisher\CRLs",
        "HKU\S-1-5-18\Software\Microsoft\SystemCertificates\TrustedPublisher\CTLs",
        "HKU\S-1-5-18\Software\Policies\Microsoft\SystemCertificates\TrustedPublisher",
        "HKU\S-1-5-18\Software\Policies\Microsoft\SystemCertificates\TrustedPublisher\Certificates",
        "HKU\S-1-5-18\Software\Policies\Microsoft\SystemCertificates\TrustedPublisher\CRLs",
        "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SPP\Clients",
        "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Profiles",
        "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Signatures\Unmanaged",
        "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement",
        "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Signatures\Managed",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products",
        "HKLM\SOFTWARE\Classes\Installer\Products",
        "HKCR\Installer\Products",
        "HKCR\Applications",
        "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ApplicationAssociationToasts",
        "HKCR\TypeLib",
        "HKCR\Interface",
        "HKCR\CLSID",
        "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts",
        "HKCU\Software\Microsoft\Search Assistant\ACMru",
        "HKLM\SOFTWARE\Microsoft\Windows Search\VolumeInfoCache",
        "HKEY_USERS\S-1-5-21-4140603452-1932478776-168934769-1003\SOFTWARE\WinRAR\DialogEditHistory\FindNames",
        "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FeatureUsage\AppSwitched",
        "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Applets\Wordpad\Recent File List",
        "HKU\S-1-5-18\Software\Policies\Microsoft\SystemCertificates\TrustedPublisher\CTLs"
        # --- Deeper Forensic Paths ---
        # --- Deeper Forensic & Anti-Cheat Paths ---
        "HKLM\SYSTEM\CurrentControlSet\Services", # Removes traces of uninstalled drivers/services
        "HKLM\SYSTEM\CurrentControlSet\Enum\SWD\PRINTENUM", # Printer device history
        "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Drivers32", # Legacy driver info
        "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Drivers32",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata",
        "HKLM\SYSTEM\CurrentControlSet\Control\Class", # Device class installations
        "HKLM\SYSTEM\CurrentControlSet\Control\PnP", # Plug and Play history
        "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options", # Can be used to debug/hook processes
        "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SilentProcessExit", # Process exit monitoring
        "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\AppCompatCache", # Shimcache
        "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\AppCompatibility", # AppCompat DB
        "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags", # AppCompat Flags
        # --- General Forensic Paths ---
        "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation",
        "HKLM\SYSTEM\MountedDevices",
        "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces",
        "HKLM\SYSTEM\CurrentControlSet\Control\Windows", # Contains ShutdownTime
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist\{5E6AB780-7743-11CF-A12B-00AA004AE837}",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist\{75048700-EF1F-11D0-9888-006097DEACF9}",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\OpenSavePidlMRU",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\OpenSaveMRU",
        # --- Even Deeper Forensic Paths ---
        "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\BootExecute",
        "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\UserList",
        "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList",
        "HKLM\SYSTEM\CurrentControlSet\Services\Wlansvc\Parameters\Profiles",
        "HKLM\SYSTEM\CurrentControlSet\Control\DeviceClasses",
        "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags",
        "HKCU\Software\Classes\Wow6432Node\Local Settings\Software\Microsoft\Windows\Shell\Bags",
        # --- Additional Forensic Paths ---
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FeatureUsage\AppLaunch",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FeatureUsage\ShowJumpView",
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband",
        # --- Advanced Anti-Cheat & Forensic Paths ---
        "HKLM\SOFTWARE\Microsoft\Rpc", # Remote Procedure Call history
        "HKLM\SOFTWARE\Classes\AppID", # DCOM application identifiers
        "HKLM\SOFTWARE\Classes\WOW6432Node\AppID",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\ShellCompatibility\Objects", # Shell object compatibility
        "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\KnownDLLs", # Known system DLLs, can be checked for modifications
        "HKLM\SYSTEM\DriverDatabase\DriverPackages", # Driver package installation info
        "HKLM\SYSTEM\CurrentControlSet\Control\Lsa\Security Packages", # LSA security packages
        "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\DriverUnload",
        "HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices", # Bluetooth device history
        "HKLM\SYSTEM\CurrentControlSet\Services\EventLog\Application", # Application event log sources
        "HKLM\SYSTEM\CurrentControlSet\Services\EventLog\Security", # Security event log sources
        "HKLM\SYSTEM\CurrentControlSet\Services\EventLog\System", # System event log sources
    )

    $hardcodedSid = 'S-1-5-21-2532382528-581214834-2534474248-1001'

    foreach ($templateKey in $regKeys) {
        # Replace the placeholder SID and HKCU with the actual current user's SID hive
        `$key = `$templateKey.Replace(`$hardcodedSid, `$currentUserSid)
        `$key = `$key.Replace('HKCU\', "HKU\`$currentUserSid\")
        
        if (Test-Path -Path $key) {
            # Show-Status is not available inside the SYSTEM context, so this message won't appear.
            # Write-Host "Removing registry key: $key" # Uncomment for debugging in a local shell
            Remove-Item -Path $key -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Special handling for WiFi and Bluetooth keys to avoid breaking connectivity.
    # Instead of deleting the parent key, we clear the subkeys containing profile/device data.
    `$specialKeys = @(
        "HKLM:\SYSTEM\CurrentControlSet\Services\Wlansvc\Parameters\Profiles",
        "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices"
    )
    foreach (`$key in `$specialKeys) {
        if (Test-Path -Path `$key) {
            # Get all child items (subkeys) and remove them, but leave the parent key intact.
            Get-ChildItem -Path `$key -Recurse -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }


    # Clear BAM (Background Activity Moderator) entries for the current user
    `$bamKeyPath = "Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\bam\UserSettings\`$currentUserSid"
    Remove-Item -LiteralPath `$bamKeyPath -Recurse -Force
"@
    Invoke-CommandAsTrustedInstaller -CommandToRun $command

    $completionMessage = "Generic registry trace cleaning complete."
    Show-Status $completionMessage "Green"
    Show-CompletionDialog $completionMessage
    Enable-Buttons
}


function Remove-RecentApps {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Cleaning recent apps and activity..."
    try {
        Invoke-Command "fsutil.exe" "behavior set disablelastaccess 1"
    } catch {}
    $recentItemsPaths = @(
        "$env:APPDATA\Microsoft\Windows\Recent",
        "$env:USERPROFILE\Recent"
    )
    foreach ($recentPath in $recentItemsPaths) {
        try {
            Remove-Item -Path "$recentPath\*" -Recurse -Force -ErrorAction SilentlyContinue
            Show-Status "Deleted files in: $recentPath"
        } catch {
            Show-Status "Failed to delete files in: $recentPath $_" "Red"
        }
    }
    # Explicitly clear RunMRU registry key (Windows+R history)
    $runMRUKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU"
    if (Test-Path $runMRUKey) {
        try {
            Remove-Item -Path "$runMRUKey\*" -Recurse -Force -ErrorAction SilentlyContinue
            Get-ItemProperty -Path $runMRUKey -Name * -Exclude '(Default)' | ForEach-Object {
                $_.PSObject.Properties | ForEach-Object { Remove-ItemProperty -Path $runMRUKey -Name $_.Name -Force -ErrorAction SilentlyContinue }
            }
            Show-Status "Cleared Windows+R RunMRU history."
        } catch {
            Show-Status "Failed to clear RunMRU history. $_" "Red"
        }
    }
    $currentUserSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $regKeys = @(
        "HKU:\$currentUserSid\Software\Microsoft\Windows\CurrentVersion\Search\RecentApps",
        "HKU:\$currentUserSid\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store",
        "HKU:\$currentUserSid\Software\Microsoft\Windows\CurrentVersion\Explorer\MountPoints2"
    )
    foreach ($key in $regKeys) {
        if (Test-Path $key) {
            try {
                Remove-Item -Path $key -Recurse -Force -ErrorAction SilentlyContinue
                New-Item -Path $key -Force -ErrorAction SilentlyContinue | Out-Null
                Show-Status "Reset registry key: $key"
            } catch {
                Show-Status "Failed to reset registry key: $key $_" "Red"
            }
        }
    }
    if (-not $IsPartOfBatch) {
        $completionMessage = "Recent apps and Windows+R history cleared."
        Show-Status $completionMessage "Green"
        Show-CompletionDialog $completionMessage
        Enable-Buttons
    }
}

function Remove-RunHistoryDeep {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Performing deep clean of run history..."

    $regKeysToClean = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist",
        "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store",
        "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Persisted"
    )

    foreach ($keyPath in $regKeysToClean) {
        if (Test-Path $keyPath) {
            Show-Status "Cleaning registry key: $keyPath"
            Remove-Item -Path "$keyPath\*" -Recurse -Force -ErrorAction SilentlyContinue
            Get-ItemProperty -Path $keyPath -Name * -Exclude '(Default)' | ForEach-Object {
                $_.PSObject.Properties | ForEach-Object { Remove-ItemProperty -Path $keyPath -Name $_.Name -Force -ErrorAction SilentlyContinue }
            }
        }
    }

    if (-not $IsPartOfBatch) {
        $completionMessage = "Deep cleanup of run history completed."
        Show-Status $completionMessage "Green"
        Show-CompletionDialog $completionMessage
        Enable-Buttons
    }
}

function Remove-FormHistory {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Cleaning form history data..."

    # Stop browsers to release file locks
    "chrome", "msedge", "brave", "opera", "firefox" | ForEach-Object {
        Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 1 # Give processes time to terminate

    # Internet Explorer and related components
    $ieFormHistoryKey = "HKCU:\Software\Microsoft\Internet Explorer\IntelliForms\Storage2"
    if (Test-Path $ieFormHistoryKey) {
        Show-Status "Removing Internet Explorer form history..."
        Remove-Item -Path $ieFormHistoryKey -Recurse -Force -ErrorAction SilentlyContinue
    }

    $appCacheFormHistory = "$env:LOCALAPPDATA\Microsoft\Windows\AppCache\FormHistory"
    if (Test-Path $appCacheFormHistory) {
        Show-Status "Removing AppCache form history..."
        Remove-Item -Path "$appCacheFormHistory\*" -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Chromium-based browsers (Web Data file)
    $chromiumPaths = @(
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Web Data",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Web Data",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Web Data",
        "$env:APPDATA\Opera Software\Opera Stable\Web Data"
    )
    $chromiumPaths | Where-Object { Test-Path $_ } | ForEach-Object {
        Show-Status "Removing form data file: $_"
        Remove-Item -Path $_ -Force -ErrorAction SilentlyContinue
    }

    # Firefox (formhistory.sqlite file)
    Get-ChildItem -Path "$env:APPDATA\Mozilla\Firefox\Profiles" -Directory | ForEach-Object {
        $formHistoryFile = Join-Path $_.FullName "formhistory.sqlite"
        if (Test-Path $formHistoryFile) {
            Show-Status "Removing Firefox form history: $formHistoryFile"
            Remove-Item -Path $formHistoryFile -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not $IsPartOfBatch) {
        $completionMessage = "Form history cleaning complete."
        Show-Status $completionMessage "Green"
        Show-CompletionDialog $completionMessage
        Enable-Buttons
    }
}

function Remove-TempFiles {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Cleaning temporary files..."

    # This list is deduplicated and expanded with more forensic artifact locations.
    $locations = @(
        # Standard Temp Locations
        "$env:TEMP\*", "$env:SystemRoot\Temp\*", "$env:LOCALAPPDATA\Temp\*",
        # Crash Dumps and Error Reporting
        "$env:LOCALAPPDATA\CrashDumps\*", "$env:ProgramData\Microsoft\Windows\WER\*", "$env:LOCALAPPDATA\Microsoft\Windows\WER\*",
        "$env:SystemRoot\Minidump\*", "$env:SystemRoot\LiveKernelReports\*",
        # Recent Files and Activity
        "$env:APPDATA\Microsoft\Windows\Recent\*", "$env:USERPROFILE\Recent\*", "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations\*",
        "$env:APPDATA\Microsoft\Windows\Recent\CustomDestinations\*",
        "$env:APPDATA\Microsoft\Office\Recent\*", # MS Office recent files
        "$env:LOCALAPPDATA\Packages\Microsoft.Windows.Photos_8wekyb3d8bbwe\LocalState\MediaDb.v1.sqlite*", # Photos App DB
        "$env:LOCALAPPDATA\Packages\Microsoft.MicrosoftStickyNotes_8wekyb3d8bbwe\LocalState\plum.sqlite*", # Sticky Notes DB
        # Windows Timeline and Activity Cache
        "$env:LOCALAPPDATA\ConnectedDevicesPlatform\L\ActivitiesCache.db*", "$env:LOCALAPPDATA\ConnectedDevicesPlatform\*",
        "$env:LOCALAPPDATA\Microsoft\Windows\Notifications\wpndatabase.db*", # Notification and Action Center DB
        "$env:LOCALAPPDATA\Microsoft\Windows\DeliveryOptimization\Logs\*", # Delivery Optimization Logs
        # Browser and Internet Caches
        "$env:LOCALAPPDATA\Microsoft\Windows\INetCache\*", "$env:LOCALAPPDATA\Microsoft\Windows\WebCache\*", "$env:LOCALAPPDATA\Microsoft\Windows\INetCookies\*",
        # System Caches
        "$env:LOCALAPPDATA\Microsoft\Windows\Caches\*", "$env:SystemRoot\System32\FxsTmp\*", "$env:SystemRoot\ServiceProfiles\LocalService\AppData\Local\FontCache\*",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db", "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db",
        # Prefetch and AppCompat
        "$env:SystemRoot\Prefetch\*", "$env:SystemRoot\appcompat\Programs\*.sdb", "$env:LOCALAPPDATA\Microsoft\Windows\AppCompat\*",
        # WMI, SleepStudy, and Software Distribution
        "$env:SystemRoot\System32\wbem\Repository\*", "$env:SystemRoot\System32\SleepStudy\*", "$env:SystemRoot\SoftwareDistribution\Download\*",
        "$env:SystemRoot\SoftwareDistribution\DataStore\Logs\edb.log",
        # Search and Defender
        "$env:ProgramData\Microsoft\Search\Data\Applications\Windows\*", "$env:ProgramData\Microsoft\Search\Data\Temp\*",
        "$env:ProgramData\Microsoft\Windows Defender\Support\*", "$env:ProgramData\Microsoft\Windows Defender\Scans\History\Service\*",
        # Diagnostic and Telemetry Data
        "$env:ProgramData\Microsoft\Diagnosis\*", "$env:ProgramData\Microsoft\DiagnosticLogCSP\*", "$env:ProgramData\Microsoft\Network\Downloader\*",
        "$env:ProgramData\Microsoft\Windows\Power Efficiency Diagnostics\*", "$env:SystemDrive\Windows\System32\WDI\LogFiles\StartupInfo\*",
        "$env:SystemDrive\Windows\System32\LogFiles\WMI\RtBackup\EtwRT*",
        # Cryptnet and other user-specific caches
        "$env:USERPROFILE\AppData\LocalLow\Microsoft\CryptnetUrlCache\MetaData\*", "$env:USERPROFILE\AppData\LocalLow\Microsoft\CryptnetUrlCache\Content\*",
        "$env:LOCALAPPDATA\Microsoft\TokenBroker\Cache\*", # UWP App Authentication Token Cache
        "$env:LOCALAPPDATA\Microsoft\Windows\GameExplorer\*", # Game Explorer Cache
        "$env:LOCALAPPDATA\Microsoft\Feeds Cache\*", # Windows Feeds Cache
        # Event Logs (brute force)
        "$env:SystemRoot\System32\winevt\Logs\*",
        # Miscellaneous Temp Files and Logs
        "$env:SystemDrive\*.log", "$env:SystemDrive\*.tmp", "$env:SystemDrive\*.old", "$env:SystemDrive\*.dmp", "$env:SystemDrive\*.gid",
        "$env:SystemDrive\*.cnt",
        "$env:SystemDrive\*.fts",
        "$env:SystemDrive\*.chk",
        "$env:SystemDrive\*.diz",
        "$env:SystemDrive\*.cock",
        "$env:SystemRoot\System32\config\systemprofile\AppData\Local\Microsoft\Windows\PowerShell\StartupProfileData-NonInteractive*",
        # SRUM Database (System Resource Usage Monitor) - Forensic goldmine
        "$env:SystemRoot\System32\sru\*", # Clears the entire SRUM database folder
        # Additional High-Value Forensic Artifacts
        "$env:LOCALAPPDATA\Microsoft\Windows\Clipboard\History\*", # Clipboard History database
        "$env:SystemRoot\System32\Tasks\*", # Scheduled Task registration files
        "$env:SystemRoot\System32\spp\store\**\tokens.dat", # Windows Activation tokens (requires special handling)
        # More diagnostic logs
        "$env:ProgramData\Microsoft\Windows\AppRepository\*",
        "$env:ProgramData\Microsoft\Windows\AppReadiness\*",
        "$env:SystemRoot\Panther\*",
        # Thumbnail Cache,
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db",
        # User-added paths & Anti-Forensics
        "$env:PUBLIC\Shared Files\*.*",
        "$env:PUBLIC\Libraries\*.*",
        "$env:LOCALAPPDATA\Microsoft\Feeds\*.*",
        "$env:windir\MEMORY.DMP",
        "$env:SystemDrive\desktop.ini",
        "$env:ProgramData\Microsoft\DataMart\PaidWiFi\Rules\*.*",
        "$env:ProgramData\Microsoft\DataMart\PaidWiFi\NetworksCache\*.*",
        "$env:LOCALAPPDATA\Microsoft\Windows\History\*.*", # Expands on IE history
        "$env:LOCALAPPDATA\Microsoft\Windows\RADC\*.*", # Reliability Analysis Diagnostics
        "$env:LOCALAPPDATA\Microsoft\CLR_v4.0\UsageLogs\*", # .NET Framework Usage Logs
        "$env:LOCALAPPDATA\Microsoft\CLR_v4.0_32\UsageLogs\*", # .NET Framework Usage Logs (32-bit)
        "$env:ProgramData\Microsoft\Windows\Power Efficiency Diagnostics\*", # Power Efficiency Diagnostics
        "$env:LOCALAPPDATA\Speech Graphics\Carnival\*.*",
        "$env:PUBLIC\Libraries\collection.dat",
        # --- Deeper Forensic File Paths ---
        "$env:LOCALAPPDATA\Microsoft\F12\Cache\DiagnosticDataViewer\datastore.edb*", # Diagnostic Data Viewer DB
        "$env:LOCALAPPDATA\Packages\Microsoft.Windows.Cortana_cw5n1h2txyewy\LocalState\DeviceSearchCache\*", # Cortana search cache
        "$env:SystemRoot\System32\LogFiles\HTTPERR\*", # HTTP.sys error logs
        "$env:LOCALAPPDATA\Microsoft\Windows\WebCacheLock.dat", # WebCache lock file
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\*.exe", # Stubs for store apps
        "$env:SystemRoot\System32\LogFiles\WUDF\*" # Windows User-Mode Driver Framework logs
    )    
    # --- Anti-Cheat Specific File Paths ---
    $locations += @(
        "$env:SystemRoot\inf\setupapi.dev.log", # Critical log of all device/driver installations
        "$env:SystemRoot\System32\wbem\Repository\*", # WMI/CIM Database, a primary target for AC scans
        "$env:ProgramData\EasyAntiCheat\*", # Common anti-cheat service
        "$env:ProgramData\BattlEye\*", # Common anti-cheat service
        "$env:LOCALAPPDATA\Valorant\Saved\Logs\*", # Valorant/Riot Vanguard logs
        "$env:ProgramData\Riot Games\Riot Client\Logs\*", # Riot Client logs
        "$env:APPDATA\EasyAntiCheat\*",
        "$env:USERPROFILE\Documents\Steam\*", # Some games store configs here
        "$env:SystemRoot\System32\LogFiles\Firewall\pfirewall.log" # Windows Firewall log
    )

    foreach ($loc in ($locations | Select-Object -Unique)) {
        Show-Status "Cleaning $loc"
        try {
            # Test if the path exists before trying to remove it
            if (Test-Path -Path $loc) {
                Remove-Item -Path $loc -Recurse -Force -ErrorAction SilentlyContinue
            }
        } catch {
            Show-Status "Could not clean $loc. It may be in use." "Red"
        }
    }

    # Special handling for recursive wildcard paths that Remove-Item doesn't handle directly
    $recursivePatterns = @(
        "$env:SystemRoot\System32\spp\store\**\data.dat",
        "$env:SystemRoot\System32\spp\store\**\tokens.dat"
    )
    foreach ($pattern in $recursivePatterns) {
        $basePath = $pattern.Split('\*\*')[0]
        $filter = Split-Path $pattern -Leaf
        if (Test-Path $basePath) {
            Show-Status "Cleaning recursive pattern: $pattern"
            Get-ChildItem -Path $basePath -Filter $filter -Recurse -File -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }

    # Clear Recycle Bin on all drives
    Get-CimInstance -ClassName Win32_LogicalDisk | ForEach-Object {
        $drive = $_.DeviceID
        $recycleBin = Join-Path -Path $drive -ChildPath "`$Recycle.Bin"
        if (Test-Path $recycleBin) {
            Show-Status "Clearing Recycle Bin on $drive"
            try {
                Remove-Item $recycleBin -Recurse -Force -ErrorAction SilentlyContinue
            } catch {
                Show-Status "Failed to empty Recycle Bin on ${drive}" "Red"
            }
        }
    }

    # Clean protected log files using TrustedInstaller
    $logPaths = @(
        "$env:windir\WindowsUpdate.log"
    )
    foreach ($path in $logPaths) {
        if (Test-Path -Path $path) {
            Show-Status "Deleting protected log: $path"
            Invoke-CommandAsTrustedInstaller -CommandToRun "Remove-Item -Path '$path' -Recurse -Force"
        }
    }

    # Special handling for waasmedic folder which has restrictive permissions
    $waasmedicPath = "$env:SystemRoot\Logs\waasmedic"
    if (Test-Path -Path $waasmedicPath) {
        takeown /f $waasmedicPath /r /d y | Out-Null
        icacls $waasmedicPath /grant administrators:F /t /q | Out-Null
        Remove-Item -Path $waasmedicPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (-not $IsPartOfBatch) {
        $completionMessage = "Temporary files cleaned."
        Show-Status $completionMessage "Green"
        Show-CompletionDialog $completionMessage
        Enable-Buttons
    }
}

function Remove-BrowsingData {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Cleaning browsing data..."

    $browsers = @{
        "chrome"  = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default"
        "msedge"  = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default"
        "firefox" = "$env:APPDATA\Mozilla\Firefox\Profiles"
        "opera"   = "$env:APPDATA\Opera Software\Opera Stable" # Note: APPDATA for Opera
        "brave"   = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default"
    }

    foreach ($name in $browsers.Keys) {
        Stop-Process -Name $name -Force -ErrorAction SilentlyContinue
        $path = $browsers[$name]
        if (Test-Path $path) {
            Show-Status "Cleaning $name data..."
            if ($name -eq "firefox") {
                Get-ChildItem -Path $path -Directory | ForEach-Object {
                    Remove-Item -Path "$($_.FullName)\cache2\entries\*" -Recurse -Force -ErrorAction SilentlyContinue
                    Remove-Item -Path "$($_.FullName)\cookies.sqlite" -Force -ErrorAction SilentlyContinue
                    Remove-Item -Path "$($_.FullName)\places.sqlite" -Force -ErrorAction SilentlyContinue
                }
            }
            else {
                Remove-Item -Path "$path\Cache\*" -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -Path "$path\Cookies" -Force -ErrorAction SilentlyContinue
                Remove-Item -Path "$path\History" -Force -ErrorAction SilentlyContinue
                Remove-Item -Path "$path\Web Data" -Force -ErrorAction SilentlyContinue
            }
        }
    }

    if (-not $IsPartOfBatch) {
        $completionMessage = "Browser data cleaning complete."
        Show-Status $completionMessage "Green"
        Show-CompletionDialog $completionMessage
        Enable-Buttons
    }
}

function Remove-UsnJournal {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Deleting USN Journal and disabling Last Access Time..."

    # Disable Last Access Time update via registry (requires SYSTEM)
    Show-Status "Disabling NTFS Last Access Time updates..."
    $command = 'Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "NtfsDisableLastAccessUpdate" -Value 1 -Type DWord -Force'
    Invoke-CommandAsTrustedInstaller -CommandToRun $command

    # Delete USN Journal
    Show-Status "Deleting USN Journal for C: drive..."
    Invoke-Command "fsutil" "usn deletejournal /d C:"
    if (-not $IsPartOfBatch) {
        $completionMessage = "USN Journal deleted and Last Access Time disabled."
        Show-Status $completionMessage "Green"
        Show-CompletionDialog $completionMessage
        Enable-Buttons
    }
}

function Remove-Shadows {
    Disable-Buttons
    Stop-Service -Name VSS -Force -ErrorAction SilentlyContinue
    Invoke-Command "fsutil.exe" "behavior set disablelastaccess 1" # This is duplicated in Remove-RecentApps, but safe to run again
    Invoke-Command "fsutil.exe" "behavior set encryptpagingfile 1"
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "ClearPageFileAtShutdown" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\$Recycle.bin" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "D:\$Recycle.bin" -Recurse -Force -ErrorAction SilentlyContinue
    Show-Status "Deleting Volume Shadow Copies..."
    Invoke-Command "vssadmin" "delete shadows /all /quiet"

    $command = @"
Remove-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SPP\Clients' -Recurse -Force -ErrorAction SilentlyContinue
"@
    Invoke-CommandAsTrustedInstaller -CommandToRun $command

    Start-Service -Name VSS -ErrorAction SilentlyContinue
    $completionMessage = "Shadow Copies deleted."
    Show-Status $completionMessage "Green"
    Show-CompletionDialog $completionMessage
    Enable-Buttons
}

function Remove-UsbHistory {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Cleaning USB plug history (requires SYSTEM)..."
    $command = @"
Remove-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR' -Recurse -Force -ErrorAction SilentlyContinue
"@
    Invoke-CommandAsTrustedInstaller -CommandToRun $command
    if (-not $IsPartOfBatch) {
        $completionMessage = "USB plug history cleaned."
        Show-Status $completionMessage "Green"
        Show-CompletionDialog $completionMessage
        Enable-Buttons
    }
}

function Remove-AllUsbHistory {
    Disable-Buttons
    Show-Status "Cleaning USB device history and drive traces..."

    # Part 1: Clean registry history (requires SYSTEM)
    Show-Status "Cleaning USB registry history (requires SYSTEM)..."
    $command = @"
    # This is more comprehensive, removing history for all USB devices, not just storage.
    # These keys are heavily protected and require SYSTEM privileges to remove.
    `$ErrorActionPreference = 'SilentlyContinue'

    Remove-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR' -Recurse -Force
    Remove-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Enum\USB' -Recurse -Force

"@
    Invoke-CommandAsTrustedInstaller -CommandToRun $command

    # Part 2: Clean traces from connected non-system drives
    Show-Status "Scanning connected drives for traces..."
    $systemDrive = $env:SystemDrive.TrimEnd('\')
    # Get all Removable (2) and Fixed (3) drives, excluding the system drive.
    $drives = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DriveType -in (2, 3) -and $_.DeviceID -ne $systemDrive }

    foreach ($drive in $drives) {
        $driveLetter = $drive.DeviceID
        $drivePath = "$($driveLetter)\"

        # Check for a common folder to identify it as a drive used by Windows
        if (Test-Path (Join-Path -Path $drivePath -ChildPath "System Volume Information")) {
            Show-Status "Cleaning traces on drive $driveLetter..."

            # Clean autorun.inf
            $autorunPath = Join-Path -Path $drivePath -ChildPath "autorun.inf"
            if (Test-Path $autorunPath) {
                Remove-Item -Path $autorunPath -Force -ErrorAction SilentlyContinue
            }

            # Clean temp files and Thumbs.db recursively
            Get-ChildItem -Path $drivePath -Include "*.tmp", "Thumbs.db" -Recurse -Force -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }

    $completionMessage = "USB device history and drive traces have been cleaned."
    Show-Status $completionMessage "Green"
    Show-CompletionDialog $completionMessage
    Enable-Buttons
}

function Remove-PrintSpooler {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Cleaning Print Spooler..."
    Stop-Service -Name "Spooler" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:windir\System32\spool\PRINTERS\*" -Force -ErrorAction SilentlyContinue
    Start-Service -Name "Spooler" -ErrorAction SilentlyContinue
    if (-not $IsPartOfBatch) {
        $completionMessage = "Print Spooler cleaned."
        Show-Status $completionMessage "Green"
        Show-CompletionDialog $completionMessage
        Enable-Buttons
    }
}

function Remove-PowershellHistory {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Cleaning PowerShell History..."
    $logName = "Microsoft-Windows-PowerShell/Operational"

    # Use a more robust method to call wevtutil.exe directly
    wevtutil.exe sl "$logName" /e:false /q:true
    if ($LASTEXITCODE -ne 0) {
        Show-Status "Failed to disable PowerShell event log. Exit Code: $LASTEXITCODE" "Red"
    }

    Remove-Item (Get-PSReadlineOption).HistorySavePath -Force -ErrorAction SilentlyContinue
    Clear-History

    wevtutil.exe sl "$logName" /e:true /q:true
    if ($LASTEXITCODE -ne 0) {
        Show-Status "Failed to re-enable PowerShell event log. Exit Code: $LASTEXITCODE" "Red"
    }
    
    $completionMessage = "PowerShell history cleared."
    Show-Status $completionMessage "Green"
    Show-CompletionDialog $completionMessage
    if (-not $IsPartOfBatch) {
        Enable-Buttons
    }
}

function Start-CipherCleanup {
    $result = [System.Windows.Forms.MessageBox]::Show("Time Consuming will take a few hours. Are you sure you want to proceed?", "Confirm Cipher Cleanup", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($result -eq 'Yes') {
        Disable-Buttons
        Show-Status "Running Cipher on C: drive... This will take a long time."
        Invoke-Command "cipher" "/w:$env:SystemDrive"
        $completionMessage = "Cipher cleanup complete."
        Show-Status $completionMessage "Green"
        Show-CompletionDialog $completionMessage
        Enable-Buttons
    }
    else {
        Show-Status "Cipher cleanup skipped."
    }
}

function Clear-EventLogs {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Clearing all event logs (requires SYSTEM)..."

    # This command block will be executed as the SYSTEM user for maximum permissions.
    $command = @"
`$ErrorActionPreference = 'SilentlyContinue'

# 1. Stop the EventLog service to release file locks.
Stop-Service -Name EventLog -Force

# 2. Use wevtutil to clear logs from the service's perspective.
`$logs = wevtutil.exe el
foreach (`$log in `$logs) {
    Write-Host "Clearing log from service: `$log"
    wevtutil.exe cl "`$log"
}

# 3. Delete the underlying .evtx files for a complete wipe.
`$logPath = Join-Path -Path `$env:SystemRoot -ChildPath 'System32\winevt\Logs'
if (Test-Path -Path `$logPath) {
    Write-Host "Deleting physical log files from `$logPath..."
    Remove-Item -Path "`$logPath\*.evtx" -Force
}

# 4. Restart the EventLog service. Windows will recreate necessary logs on start.
Set-Service -Name EventLog -StartupType Automatic
Start-Service -Name EventLog
"@

    Invoke-CommandAsTrustedInstaller -CommandToRun $command

    if (-not $IsPartOfBatch) {
        $completionMessage = "All event logs have been aggressively cleared."
        Show-Status $completionMessage "Green"
        Show-CompletionDialog $completionMessage
        Enable-Buttons
    }
}

function Clear-EventLogsEnd {
    Disable-Buttons
    Show-Status "Re-enabling event logs..."
    $powershellLogName = "Microsoft-Windows-PowerShell/Operational"

    Show-Status "Re-enabling Application Event Logs..."
    Invoke-Command "wevtutil.exe" "set-log Application /enabled:true"
    Show-Status "Re-Enabling Security Event Logs..."
    Invoke-Command "wevtutil.exe" "set-log Security /enabled:true"
    Show-Status "Re-Enabling System Event Logs..."
    Invoke-Command "wevtutil.exe" "set-log System /enabled:true"
    Show-Status "Re-enabling PowerShell event log..."
    Invoke-Command "wevtutil.exe" "set-log `"$powershellLogName`" /enabled:true /quiet:true"
    $completionMessage = "Event logs have been re-enabled."
    Show-Status $completionMessage "Green"
    Show-CompletionDialog $completionMessage
    Enable-Buttons
}

function Remove-NvidiaCache {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Cleaning NVIDIA cache files..."
    Stop-Process -Name "nv*" -Force -ErrorAction SilentlyContinue

    $locations = @(
    "$env:LOCALAPPDATA\NVIDIA\DXCache\*",
    "$env:LOCALAPPDATA\NVIDIA\GLCache\*",
    "$env:LOCALAPPDATA\NVIDIA Corporation\NV_Cache\*",
    "$env:ProgramData\NVIDIA Corporation\Downloader\*",
    "$env:LOCALAPPDATA\NVIDIA\*",
    "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA Share\*",
    "$env:LOCALAPPDATA\NVIDIA Corporation\NvNode\*",
    "$env:LOCALAPPDATA\NVIDIA Corporation\NvTelemetry\*",
    "$env:ProgramData\NVIDIA Corporation\GeForce Experience\Logs\*",
    "$env:LOCALAPPDATA\NVIDIA Corporation\GfeBridges\*",
    "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA GeForce Experience\*",
    "$env:ProgramData\NVIDIA Corporation\NvTelemetry\*",
    "$env:ProgramData\NVIDIA Corporation\Drs\*",
    "$env:LOCALAPPDATA\NVIDIA Corporation\NvContainer\*"
    )
    foreach ($loc in $locations) {
        Show-Status "Cleaning $loc"
        Remove-Item -Path $loc -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    $command = @"
Remove-Item 'HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm\FTS' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item 'HKLM:\SYSTEM\CurrentControlSet\Services\NvTelemetryContainer' -Recurse -Force -ErrorAction SilentlyContinue
"@
    Invoke-CommandAsTrustedInstaller -CommandToRun $command

    if (-not $IsPartOfBatch) {
        $completionMessage = "NVIDIA cache cleaned."
        Show-Status $completionMessage "Green"
        Show-CompletionDialog $completionMessage
        Enable-Buttons
    }
}

function Remove-AmdCache {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Cleaning AMD cache files..."
    Stop-Process -Name "*amd*" -Force -ErrorAction SilentlyContinue

    $locations = @(
    "$env:LOCALAPPDATA\AMD\CNext\*",
    "$env:LOCALAPPDATA\AMD\DxCache\*",
    "$env:LOCALAPPDATA\AMD\GLCache\*",
    "$env:LOCALAPPDATA\AMD\VkCache\*",
    "$env:LOCALAPPDATA\AMD\Radeonsoftware\*",
    "$env:ProgramData\AMD\Radeonsoftware\*",
    "$env:ProgramData\AMD\Telemetry\*",
    "$env:LOCALAPPDATA\AMD\*",
    "$env:ProgramData\AMD\*"
    )
    foreach ($path in $locations) {
    if (Test-Path -Path $path) {
        Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
    }
    }

    $command = @"
Remove-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\amdkmdap\FTS' -Force -ErrorAction SilentlyContinue
Remove-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\amdkmdap' -Force -ErrorAction SilentlyContinue

`$classKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
`$subkeys = Get-ChildItem -Path `$classKey -ErrorAction SilentlyContinue | Where-Object { `$_ .PSChildName -like '0*' }
foreach (`$subkey in `$subkeys) {
    Remove-ItemProperty -Path `$subkey.PSPath -Name 'EnableUlps' -Force -ErrorAction SilentlyContinue
}
"@
    Invoke-CommandAsTrustedInstaller -CommandToRun $command

    if (-not $IsPartOfBatch) {
        $completionMessage = "AMD cache cleaned."
        Show-Status $completionMessage "Green"
        Show-CompletionDialog $completionMessage
        Enable-Buttons
    }
}

function Remove-ShimCache {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Flushing Shim Cache and Temp Internet Files..."
    try {
        Invoke-Command "rundll32.exe" "apphelp.dll,ShimFlushCache"
        Show-Status "ShimFlushCache called successfully."
    } catch {
        Show-Status "Failed to flush ShimCache via rundll32. $_" "Red"
    }

    # Clear Temporary Internet Files
    try {
        Show-Status "Clearing Temporary Internet Files via RunDll32..."
        Invoke-Command "RunDll32.exe" "InetCpl.cpl,ClearMyTracksByProcess 8"
        Show-Status "Temporary Internet Files cleanup command issued."
    } catch {
        Show-Status "Failed to clear Temporary Internet Files. $_" "Red"
    }
    $shimCacheRegKeys = @(
        'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\AppCompatCache',
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\AppCompatCache',
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store'
    )
    foreach ($regKey in $shimCacheRegKeys) {
        if (Test-Path $regKey) {
            try {
                Remove-Item -Path $regKey -Recurse -Force -ErrorAction SilentlyContinue
                Show-Status "Deleted registry key: $regKey"
            } catch {
                Show-Status "Failed to delete registry key $regKey. $_" "Red"
            }
        }
    }
    if (-not $IsPartOfBatch) {
        $completionMessage = "ShimCache and Temp Internet Files cleaning complete."
        Show-Status $completionMessage "Green"
        Show-CompletionDialog $completionMessage
        Enable-Buttons
    }
}

function Remove-Amcache {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Cleaning Amcache..."
    try {
        Stop-Service -Name "AeLookupSvc" -Force -ErrorAction SilentlyContinue
    } catch {
        Show-Status "Failed to stop AeLookupSvc. $_" "Red"
    }
    try {
        Invoke-Command "rundll32.exe" "kernel32.dll,BaseFlushAppcompatCache"
    } catch {
        Show-Status "Failed to flush appcompat cache. $_" "Red"
    }
    $amcacheFiles = @(
        "$env:SystemRoot\appcompat\Programs\RecentFileCache.bcf",
        "$env:SystemRoot\appcompat\Programs\Amcache.hve"
        "$env:SystemRoot\appcompat\Programs\Amcache.hve.LOG1",
        "$env:SystemRoot\appcompat\Programs\Amcache.hve.LOG2"
    )
    foreach ($file in $amcacheFiles) {
        if (Test-Path $file) {
            try {
                Remove-Item -Path $file -Force -ErrorAction SilentlyContinue
                Show-Status "Deleted: $file"
            } catch {
                Show-Status "Failed to delete $file. $_" "Red"
            }
        }
    }
    $amcacheRegKeys = @(
        'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\AppCompatCache',
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\AppCompatCache',
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store'
    )
    foreach ($regKey in $amcacheRegKeys) {
        if (Test-Path $regKey) {
            try {
                Remove-Item -Path $regKey -Recurse -Force -ErrorAction SilentlyContinue
                Show-Status "Deleted registry key: $regKey"
            } catch {
                Show-Status "Failed to delete registry key $regKey. $_" "Red"
            }
        }
    }
    try {
        Start-Service -Name "AeLookupSvc" -ErrorAction SilentlyContinue
    } catch {
        Show-Status "Failed to restart AeLookupSvc. $_" "Red"
    }
    if (-not $IsPartOfBatch) {
        $completionMessage = "Amcache cleaning complete."
        Show-Status $completionMessage "Green"
        Show-CompletionDialog $completionMessage
        Enable-Buttons
    }
}

function Remove-DefenderHistory {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Performing deep clean of Defender history (requires SYSTEM)..."

    # This command block will run as SYSTEM to manage the service and delete protected files.
    $command = @"
`$ErrorActionPreference = 'SilentlyContinue'

# Check for Tamper Protection. If it's on, we can't stop the service.
`$tamperProt = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features" -Name "TamperProtection" -ErrorAction SilentlyContinue
if (`$tamperProt -and `$tamperProt.TamperProtection -ne 4) { # 4 is 'off', 5 is 'on'
    # This Write-Host will appear in the temp script log, not the GUI.
    Write-Host "Tamper Protection is enabled. Cannot stop WinDefend service."
    exit 1
}

Write-Host "Stopping Windows Defender service..."
Stop-Service -Name "WinDefend" -Force

`$defenderPath = Join-Path -Path "`$env:ProgramData" -ChildPath "Microsoft\Windows Defender"

# Delete the contents of the folders, not the folders themselves, to avoid issues.
Write-Host "Removing Defender file history, quarantine, and support logs..."
Remove-Item -Path (Join-Path -Path `$defenderPath -ChildPath "Scans\History\*") -Recurse -Force
Remove-Item -Path (Join-Path -Path `$defenderPath -ChildPath "Quarantine\*") -Recurse -Force
Remove-Item -Path (Join-Path -Path `$defenderPath -ChildPath "Support\*") -Recurse -Force

# Clear and recreate the registry keys where threat metadata is stored.
Write-Host "Removing Defender registry traces..."
Remove-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Threats' -Recurse -Force
Remove-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Quarantine' -Recurse -Force
New-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Threats' -Force | Out-Null
New-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Quarantine' -Force | Out-Null

Write-Host "Starting Windows Defender service..."
Start-Service -Name "WinDefend"

# Also clear related event logs
Write-Host "Clearing Defender event logs..."
"Microsoft-Windows-Windows Defender/Operational", "Microsoft-Windows-Windows Defender/WHC" | ForEach-Object {
    wevtutil.exe cl "`$_"
}
"@

    try {
        Invoke-CommandAsTrustedInstaller -CommandToRun $command -ErrorAction Stop
        $completionMessage = "Windows Defender deep clean complete."
        Show-Status $completionMessage "Green"
    }
    catch {
        $completionMessage = "Defender clean failed. Disable Tamper Protection in Windows Security first."
        Show-Status $completionMessage "Red"
    }

    if (-not $IsPartOfBatch) {
        Show-CompletionDialog $completionMessage
        Enable-Buttons
    }
}

function Remove-WmiRepository {
    Disable-Buttons
    Show-Status "Resetting WMI Repository..."
    
    # Stop the WMI service. The -Force parameter will also stop dependent services.
    Stop-Service -Name "winmgmt" -Force -ErrorAction SilentlyContinue
    
    # Reset the repository
    Invoke-Command "winmgmt" "/resetrepository"
    
   
    
    $completionMessage = "WMI Repository has been reset."
    Show-Status $completionMessage "Green"
    Show-CompletionDialog $completionMessage
    Enable-Buttons
}

function Remove-SteamAccounts {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Resetting Steam accounts and cache..."

    # Stop Steam process
    Stop-Process -Name "steam" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    # Get Steam installation path from registry
    $steamPath = Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty "SteamPath"

    if (-not [string]::IsNullOrEmpty($steamPath)) {
        Show-Status "Steam found at: $steamPath"

        # Folders to delete within Steam directory
        $foldersToDelete = @(
            "$steamPath\appcache",
            "$steamPath\appcache\httpcache",
            "$steamPath\config",
            "$steamPath\config\htmlcache",
            "$steamPath\userdata",
            "$steamPath\htmlcache",
            "$steamPath\logs",
            "$steamPath\dumps",
            "$steamPath\depotcache",
            "$steamPath\steamapps\shadercache"
        )

        # Files to delete (Steam Guard files)
        $filesToDelete = @(
            "$steamPath\ssfn*"
        )

        ($foldersToDelete | Select-Object -Unique) | ForEach-Object { if (Test-Path $_) { Show-Status "Removing folder: $_"; Remove-Item -Path $_ -Recurse -Force -ErrorAction SilentlyContinue } }
        $filesToDelete | ForEach-Object { if (Test-Path $_) { Show-Status "Removing file(s): $_"; Remove-Item -Path $_ -Force -ErrorAction SilentlyContinue } }
    }
    else {
        Show-Status "Steam installation path not found in registry." "Red"
    }

    # Clean other known Steam locations
    $otherSteamPaths = @(
        "$env:ProgramData\Steam\RtmpStore\*",
        "$env:LOCALAPPDATA\Steam\htmlcache\*",
        "$env:LOCALAPPDATA\Steam\widevine\*"
    )
    foreach ($path in $otherSteamPaths) {
        if (Test-Path $path) {
            Show-Status "Removing path: $path"
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Remove login information from registry
    $steamRegKey = "HKCU:\Software\Valve\Steam"
    if (Test-Path $steamRegKey) {
        Show-Status "Clearing Steam registry entries..."
        Remove-ItemProperty -Path $steamRegKey -Name "AutoLoginUser" -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $steamRegKey -Name "RememberPassword" -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$steamRegKey\Apps" -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (-not $IsPartOfBatch) { $completionMessage = "Steam account and cache reset complete. You will need to log in again."; Show-Status $completionMessage "Green"; Show-CompletionDialog $completionMessage; Enable-Buttons }
}

function Remove-EpicGames {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Cleaning Epic Games Launcher traces..."

    # 1. Stop Epic Games processes
    Show-Status "Stopping Epic Games Launcher..."
    Stop-Process -Name "EpicGamesLauncher" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    # 2. Remove cache, logs, and user data folders
    $foldersToDelete = @(
        "$env:LOCALAPPDATA\EpicGamesLauncher",
        "$env:PROGRAMDATA\Epic" # Contains manifests and installation data
    )

    foreach ($folder in $foldersToDelete) {
        if (Test-Path $folder) {
            Show-Status "Removing folder: $folder"
            Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # 3. Remove registry keys for settings and login info
    $regKeysToDelete = @( "HKCU:\Software\Epic Games", "HKLM:\SOFTWARE\Epic Games", "HKLM:\SOFTWARE\WOW6432Node\Epic Games" )
    foreach ($key in $regKeysToDelete) {
        if (Test-Path $key) { Show-Status "Removing registry key: $key"; Remove-Item -Path $key -Recurse -Force -ErrorAction SilentlyContinue }
    }

    if (-not $IsPartOfBatch) { $completionMessage = "Epic Games Launcher traces cleaned."; Show-Status $completionMessage "Green"; Show-CompletionDialog $completionMessage; Enable-Buttons }
}

function Remove-RockstarCache {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Cleaning Rockstar Games Launcher cache and logins..."

    # Stop Rockstar processes
    "RockstarService", "Launcher" | ForEach-Object {
        Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 1

    # Define paths for cache, logs, and user data
    $foldersToDelete = @(
        "$env:USERPROFILE\Documents\Rockstar Games\Launcher",
        "$env:USERPROFILE\Documents\Rockstar Games\Social Club",
        "$env:LOCALAPPDATA\Rockstar Games",
        "$env:PROGRAMDATA\Rockstar Games" # This requires admin, which the script should have
    )

    $foldersToDelete | ForEach-Object { if (Test-Path $_) { Show-Status "Removing folder: $_"; Remove-Item -Path $_ -Recurse -Force -ErrorAction SilentlyContinue } }

    # Remove registry keys for saved settings and logins
    $regKey = "HKCU:\Software\Rockstar Games"
    if (Test-Path $regKey) { Show-Status "Removing Rockstar Games registry settings..."; Remove-Item -Path $regKey -Recurse -Force -ErrorAction SilentlyContinue }

    if (-not $IsPartOfBatch) { $completionMessage = "Rockstar Games Launcher cache and login data cleared."; Show-Status $completionMessage "Green"; Show-CompletionDialog $completionMessage; Enable-Buttons }
}

function Remove-DiscordCache {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Cleaning Discord cache and traces..."

    # 1. Stop all versions of Discord to release file locks
    $discordProcesses = @("Discord", "DiscordPTB", "DiscordCanary")
    Show-Status "Stopping Discord processes..."
    $discordProcesses | ForEach-Object { Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 1 # Give time for processes to terminate

    # 2. Define paths to clean for all Discord versions
    $discordPaths = @(
        # Standard Discord
        "$env:APPDATA\discord\Cache",
        "$env:APPDATA\discord\Code Cache",
        "$env:APPDATA\discord\GPUCache",
        "$env:APPDATA\discord\logs",
        # Discord PTB (Public Test Build)
        "$env:APPDATA\discordptb\Cache",
        "$env:APPDATA\discordptb\Code Cache",
        "$env:APPDATA\discordptb\GPUCache",
        "$env:APPDATA\discordptb\logs",
        # Discord Canary (Bleeding-edge)
        "$env:APPDATA\discordcanary\Cache",
        "$env:APPDATA\discordcanary\Code Cache",
        "$env:APPDATA\discordcanary\GPUCache",
        "$env:APPDATA\discordcanary\logs"
    )

    # 3. Loop through paths and remove them
    foreach ($path in ($discordPaths | Select-Object -Unique)) {
        if (Test-Path $path) { Show-Status "Removing: $path"; Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # 4. Finalize and show completion message if not part of a batch operation
    if (-not $IsPartOfBatch) { $completionMessage = "Discord cache and traces cleaned."; Show-Status $completionMessage "Green"; Show-CompletionDialog $completionMessage; Enable-Buttons }
}

function Remove-TracesOnExit {
    # This is a silent function that runs on exit to clean up traces of the tool itself.
    # It does not use GUI feedback functions like Show-Status or Show-CompletionDialog.

    # --- Clean PowerShell History (Silent) ---
    try {
        Remove-Item (Get-PSReadlineOption).HistorySavePath -Force -ErrorAction SilentlyContinue
        Clear-History
    } catch {} # Keep try/catch for robustness, even if silent.

    # --- Clean Recent Apps (Silent) ---
    try {
        $recentItemsPath = "$env:APPDATA\Microsoft\Windows\Recent"
        Remove-Item -Path "$recentItemsPath\AutomaticDestinations\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$recentItemsPath\CustomDestinations\*" -Recurse -Force -ErrorAction SilentlyContinue

        $currentUserSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $regKey = "HKU:\$currentUserSid\Software\Microsoft\Windows\CurrentVersion\Search\RecentApps"
        if (Test-Path $regKey) {
            Remove-Item -Path $regKey -Recurse -Force -ErrorAction SilentlyContinue
            New-Item -Path $regKey -Force -ErrorAction SilentlyContinue | Out-Null
        }
    } catch {} # Keep try/catch for robustness, even if silent.
}

function Remove-XboxDeep {
    Disable-Buttons
    Show-Status "Performing deep clean of Xbox components (requires SYSTEM)..."

    $command = @"
`$ErrorActionPreference = 'SilentlyContinue'

# 1. Stop all Xbox and Gaming related services
"GamingServices", "GamingServicesNet", "XblAuthManager", "XblGameSave", "XboxGipSvc", "XboxNetApiSvc" | ForEach-Object {
    Stop-Service -Name `$_ -Force
}

# 2. Delete Xbox-related AppData packages and files
`$appDataPaths = @(
    "$env:LOCALAPPDATA\Packages\Microsoft.XboxGamingOverlay_8wekyb3d8bbwe",
    "$env:LOCALAPPDATA\Packages\Microsoft.Xbox.TCUI_8wekyb3d8bbwe",
    "$env:LOCALAPPDATA\Packages\Microsoft.XboxApp_8wekyb3d8bbwe",
    "$env:LOCALAPPDATA\Packages\Microsoft.XboxIdentityProvider_*",
    "$env:LOCALAPPDATA\Packages\Microsoft.GamingApp_*",
    "$env:LOCALAPPDATA\Packages\Microsoft.GamingServices_*",
    "$env:LOCALAPPDATA\Packages\Microsoft.XboxSpeechToTextOverlay_*",
    "$env:ProgramData\Microsoft\XboxLive",
    "$env:LOCALAPPDATA\Microsoft\XboxLive",
    "$env:LOCALAPPDATA\Microsoft\GamingServices",
    "$env:SystemRoot\SoftwareDistribution\EventCache\{BEB0A93F-8B55-4157-AE89-CDF4F261A773}.bin"
)
foreach (`$path in (`$appDataPaths | Select-Object -Unique)) {
    Remove-Item -Path `$path -Recurse -Force
}

# 3. Delete Xbox-related registry keys
`$currentUserSid = (Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty UserName).Split('\')[1]
`$userSidObj = New-Object System.Security.Principal.NTAccount(`$currentUserSid)
`$currentUserSid = `$userSidObj.Translate([System.Security.Principal.SecurityIdentifier]).Value

`$regKeysToDelete = @(
        "HKCU:\Software\Microsoft\GameBar",
        "HKCU:\Software\Microsoft\Games",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR",
        "HKCU:\Software\Microsoft\XboxLive",
        "HKCU:\Software\Microsoft\Xbox",
        "HKCU:\System\GameConfigStore",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Applications\Microsoft.Xbox*",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\`$currentUserSid\Microsoft.Xbox*",
        "HKLM:\SYSTEM\CurrentControlSet\Services\GamingServices",
        "HKLM:\SYSTEM\CurrentControlSet\Services\GamingServicesNet",
        "HKLM:\SYSTEM\CurrentControlSet\Services\XblAuthManager",
        "HKLM:\SYSTEM\CurrentControlSet\Services\XblGameSave",
        "HKLM:\SYSTEM\CurrentControlSet\Services\XboxGipSvc",
        "HKLM:\SYSTEM\CurrentControlSet\Services\XboxNetApiSvc",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\Package\Index\PackageFullName\Microsoft.XboxGameOverlay_1.41.24001.0_neutral_split.scale-100_8wekyb3d8bbwe",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\Package\Index\PackageFullName\Microsoft.XboxGameOverlay_1.41.24001.0_neutral_split.scale-100_8wekyb3d8bbwe\182",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\Package\Index\PackageFullName\Microsoft.XboxGameOverlay_1.41.24001.0_neutral_~_8wekyb3d8bbwe",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\Package\Index\PackageFullName\Microsoft.XboxGameOverlay_1.41.24001.0_neutral_~_8wekyb3d8bbwe\180",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\Package\Index\PackageFullName\Microsoft.XboxGameOverlay_1.41.24001.0_x64__8wekyb3d8bbwe",
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\Package\Index\PackageFullName\Microsoft.XboxGameOverlay_1.41.24001.0_x64__8wekyb3d8bbwe\181"
    )
    foreach (`$key in `$regKeysToDelete) {
        Remove-Item -Path `$key -Recurse -Force
    }
"@
    Invoke-CommandAsTrustedInstaller -CommandToRun $command

    $completionMessage = "Xbox deep clean complete. A restart may be required."
    Show-Status $completionMessage "Green"
    Show-CompletionDialog $completionMessage
    Enable-Buttons
}

function Remove-ImGuiIniFiles {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Cleaning ImGui .ini files..."
    $itemsDeleted = 0
    $searchPath = "$env:APPDATA"
    
    try {
        $files = Get-ChildItem -Path $searchPath -Filter "imgui.ini" -Recurse -File -ErrorAction SilentlyContinue
        if ($files) {
            foreach ($file in $files) {
                try {
                    Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                    Show-Status "Deleted: $($file.FullName)"
                    $itemsDeleted++
                } catch {
                    Show-Status "Failed to delete: $($file.FullName) - $_" "Red"
                }
            }
        }
    } catch {
        Show-Status "Error searching for ImGui files: $_" "Red"
    }

    if (-not $IsPartOfBatch) {
        $completionMessage = if ($itemsDeleted -gt 0) { "ImGui .ini file cleaning complete. Removed $itemsDeleted file(s)." } else { "No ImGui .ini files found in $searchPath." }
        Show-Status $completionMessage "Green"
        Show-CompletionDialog $completionMessage
        Enable-Buttons
    }
}

function Remove-NirSoftTraces {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Cleaning all NirSoft program traces..."

    # 1. Remove the main NirSoft registry hive for the current user
    $nirsoftRegKey = 'HKCU:\Software\NirSoft'
    if (Test-Path $nirsoftRegKey) {
        Show-Status "Removing NirSoft registry hive: $nirsoftRegKey"
        Remove-Item -Path $nirsoftRegKey -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 2. Remove NirSoft AppData folders where config files (.cfg) are often stored
    $nirsoftAppDataPaths = @(
        "$env:APPDATA\NirSoft",
        "$env:LOCALAPPDATA\NirSoft" # Less common, but good to check
    )
    foreach ($path in $nirsoftAppDataPaths) {
        if (Test-Path $path) {
            Show-Status "Removing NirSoft AppData folder: $path"
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # 3. Finalize
    if (-not $IsPartOfBatch) { $completionMessage = "NirSoft traces cleaned."; Show-Status $completionMessage "Green"; Show-CompletionDialog $completionMessage; Enable-Buttons }
}

function Remove-OSForensicsLogs {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Starting complete removal of OSForensics..."

    # 1. Stop OSForensics processes
    $processName = "osf"
    $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
    if ($processes) {
        Show-Status "Stopping OSForensics process(es)..."
        $processes | Stop-Process -Force -ErrorAction SilentlyContinue
        Show-Status "OSForensics process(es) stopped."
    }

    # 2. Find and run uninstaller, then force-remove directories
    $uninstallKeyPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    $osfUninstallEntry = $null
    foreach ($keyPath in $uninstallKeyPaths) {
        if (Test-Path $keyPath) {
            $osfUninstallEntry = Get-ChildItem -Path $keyPath | Get-ItemProperty | Where-Object { $_.DisplayName -like "OSForensics*" } | Select-Object -First 1
            if ($osfUninstallEntry) { break }
        }
    }

    if ($osfUninstallEntry -and $osfUninstallEntry.UninstallString) {
        Show-Status "Found OSForensics uninstaller. Attempting silent uninstall..."
        $uninstallCommand = $osfUninstallEntry.UninstallString -replace '/I', '/X' -replace 'msiexec.exe', ''
        $uninstallArgs = "$uninstallCommand /qn"
        Invoke-Command "msiexec.exe" $uninstallArgs
        Show-Status "Official uninstaller finished."
    }

    $installDirs = @(
        "$env:ProgramFiles\OSForensics",
        "$env:ProgramFiles(x86)\OSForensics"
    )
    if($osfUninstallEntry.InstallLocation) { $installDirs += $osfUninstallEntry.InstallLocation }

    foreach ($dir in ($installDirs | Select-Object -Unique)) {
        if (Test-Path $dir) {
            Show-Status "Removing installation directory: $dir"
            Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # 3. Remove user-specific data, logs, and case files
    Show-Status "Removing user-specific data, logs, and artifacts..."
    $userArtifactPaths = @(
        (Join-Path $env:APPDATA "PassMark\OSForensics"),
        (Join-Path $env:LOCALAPPDATA "PassMark\OSForensics"),
        (Join-Path ([Environment]::GetFolderPath('MyDocuments')) "OSForensics Cases"),
        (Join-Path ([Environment]::GetFolderPath('MyDocuments')) "OSForensics")
    )
    $userArtifactPaths | ForEach-Object { if (Test-Path $_) { Show-Status "Removing artifact directory: $_"; Remove-Item -Path $_ -Recurse -Force -ErrorAction SilentlyContinue } }

    # 4. Remove registry keys
    Show-Status "Removing registry keys..."
    $registryKeys = @( "HKCU:\SOFTWARE\PassMark\OSForensics", "HKLM:\SOFTWARE\PassMark\OSForensics", "HKLM:\SOFTWARE\WOW6432Node\PassMark\OSForensics" )
    if ($osfUninstallEntry) { $registryKeys += $osfUninstallEntry.PSPath.ToString() }
    $registryKeys | Select-Object -Unique | ForEach-Object { if (Test-Path $_) { Show-Status "Removing registry key: $_"; Remove-Item -Path $_ -Recurse -Force -ErrorAction SilentlyContinue } }

    # 5. Remove shortcuts
    Show-Status "Removing shortcuts..."
    $shortcutPaths = @( (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\OSForensics"), (Join-Path $env:ALLUSERSPROFILE "Microsoft\Windows\Start Menu\Programs\OSForensics"), (Join-Path $env:USERPROFILE "Desktop\OSForensics.lnk"), (Join-Path $env:PUBLIC "Desktop\OSForensics.lnk") )
    $shortcutPaths | ForEach-Object { if (Test-Path $_) { Show-Status "Removing shortcut/folder: $_"; Remove-Item -Path $_ -Recurse -Force -ErrorAction SilentlyContinue } }

    if (-not $IsPartOfBatch) { $completionMessage = "OSForensics removal process completed."; Show-Status $completionMessage "Green"; Show-CompletionDialog $completionMessage; Enable-Buttons }
}

function Remove-RegistryJunk {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Cleaning registry junk (obsolete keys)..."
    $command = @"
`$obsoleteKeys = @(
    'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU',
    'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\MenuOrder\Start Menu',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FeatureUsage\AppSwitched'
)
foreach (`$key in `$obsoleteKeys) {
    if (Test-Path `$key) {
        Remove-Item -Path `$key -Recurse -Force -ErrorAction SilentlyContinue
    }
}
"@
    Invoke-CommandAsTrustedInstaller -CommandToRun $command
    if (-not $IsPartOfBatch) {
        $completionMessage = "Registry junk cleaning attempted."
        Show-Status $completionMessage "Green"
        Show-CompletionDialog $completionMessage
        Enable-Buttons
    }
}

function Reset-DataUsage {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Resetting network data usage and diagnostics..."

    # Reset SRUM database
    $dataPath = "$env:ProgramData\Microsoft\Windows\Sru\srudb.dat"
    if (Test-Path $dataPath) {
        Show-Status "Resetting SRUM database (srudb.dat)..."
        Stop-Service -Name "DPS" -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $dataPath -Force -ErrorAction SilentlyContinue
        Start-Service -Name "DPS" -ErrorAction SilentlyContinue
    }

    # Delete saved WLAN profiles
    Show-Status "Deleting saved WLAN profiles..."
    Invoke-Command "netsh" "wlan delete profile name=* i=*"

    # Flush DNS
    Show-Status "Flushing DNS cache..."
    Invoke-Command "ipconfig" "/flushdns"

    # Delete Internet Settings registry keys
    Show-Status "Deleting Internet Settings registry keys..."
    Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Connections" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\5.0\Cache" -Recurse -Force -ErrorAction SilentlyContinue

    # Delete various diagnostic and error reporting logs
    Show-Status "Deleting diagnostic and WER logs..."
    $logPathsToDelete = @( "$env:LOCALAPPDATA\Microsoft\Windows\WER\*", "$env:ProgramData\Microsoft\DiagnosticLogCSP\*", "$env:ProgramData\Microsoft\Network\Downloader\*", "$env:ProgramData\Microsoft\Diagnosis\*", "$env:ProgramData\Microsoft\Windows\Power Efficiency Diagnostics\*" )
    foreach ($path in $logPathsToDelete) {
        if (Test-Path $path) { Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue }
    }

    if (-not $IsPartOfBatch) {
        $completionMessage = "Network data usage and diagnostics have been reset."
        Show-Status $completionMessage "Green"
        Show-CompletionDialog $completionMessage
        Enable-Buttons
    }
}

function Remove-ProcessStrings {
    param(
        [string[]]$ProcessNames = @('DPS', 'lsass', 'csrss', 'explorer', 'chrome', 'msedge', 'firefox', 'opera', 'brave'),
        [switch]$RestartExplorer
    )
    Disable-Buttons
    Show-Status "Clearing memory for selected processes..."

    # Define critical processes that should NOT be terminated.
    $criticalProcesses = @('lsass', 'csrss', 'dps')

    foreach ($procName in $ProcessNames) {
        if ($criticalProcesses -contains $procName.ToLower()) {
            # For critical processes, only attempt the "safe" working set trim.
            $procs = Get-Process -Name $procName -ErrorAction SilentlyContinue
            foreach ($proc in $procs) {
                try {
                    $proc.Refresh()
                    $proc.MinWorkingSet = $proc.MinWorkingSet
                    $proc.MaxWorkingSet = $proc.MaxWorkingSet
                    Show-Status "Requested working set trim for critical process: $($proc.ProcessName)"
                } catch {
                    Show-Status "Failed to trim memory for: $($proc.ProcessName) (PID: $($proc.Id)) $_" "Red"
                }
            }
        }
        else {
            # For non-critical processes, terminate them to guarantee memory is cleared.
            if (Get-Process -Name $procName -ErrorAction SilentlyContinue) {
                Show-Status "Terminating '$procName' to clear memory..."
                Stop-Process -Name $procName -Force -ErrorAction SilentlyContinue
            }
        }
    }

    if ($RestartExplorer) {
        Show-Status "Restarting Windows Explorer..."
        Start-Process -FilePath "explorer.exe" -ErrorAction SilentlyContinue
    }

    $completionMessage = "Memory clearing operation completed for specified processes."
    Show-Status $completionMessage "Green"
    Show-CompletionDialog $completionMessage
    Enable-Buttons
}

function Remove-BrowserMemoryStrings {
    Disable-Buttons
    Show-Status "Clearing browser memory by terminating processes..."
    $browserProcesses = @('chrome', 'msedge', 'firefox', 'opera', 'brave')
    $processesTerminated = 0

    foreach ($procName in $browserProcesses) {
        $procs = Get-Process -Name $procName -ErrorAction SilentlyContinue
        if ($procs) {
            Show-Status "Terminating all '$procName' processes..."
            Stop-Process -Name $procName -Force -ErrorAction SilentlyContinue
            $processesTerminated++
        }
    }

    $completionMessage = if ($processesTerminated -gt 0) { "Browser processes terminated to clear memory." } else { "No running browser processes found to terminate." }
    Show-Status $completionMessage "Green"
    Show-CompletionDialog $completionMessage
    Enable-Buttons
}

function Remove-DirectXCache {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Cleaning DirectX Shader Cache..."

    "steam", "EpicGamesLauncher", "RockstarGamesLauncher", "Origin", "EADesktop", "Battle.net", "RiotClientServices" | ForEach-Object {
        Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 1

    $locations = @(
        "$env:LOCALAPPDATA\D3DSCache\*",
        "$env:LOCALAPPDATA\NVIDIA\DXCache\*",
        "$env:LOCALAPPDATA\AMD\DxCache\*"
    )

    foreach ($loc in ($locations | Select-Object -Unique)) {
        if (Test-Path $loc) {
            Show-Status "Cleaning $loc"
            Remove-Item -Path $loc -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not $IsPartOfBatch) {
        $completionMessage = "DirectX shader cache cleaned."
        Show-Status $completionMessage "Green"
        Show-CompletionDialog $completionMessage
        Enable-Buttons
    }
}

function Remove-CpuCaches {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Cleaning CPU-related OS caches..."
    # NOTE: This function does not clean the CPU's hardware L1/L2/L3 cache, as that is impossible via software.
    # Instead, it targets various OS-level caches (Font, Icon, Prefetch) that can be safely cleared.
    Stop-Service -Name "FontCache" -Force -ErrorAction SilentlyContinue
    $locations = @( "$env:SystemRoot\ServiceProfiles\LocalService\AppData\Local\FontCache\*", "$env:LOCALAPPDATA\Microsoft\Windows\FontCache\*", "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db", "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db", "$env:SystemRoot\Prefetch\*" )
    foreach ($loc in ($locations | Select-Object -Unique)) {
        if (Test-Path $loc) {
            Show-Status "Cleaning $loc"
            Remove-Item -Path $loc -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Add L2/L3 cache size registry tweak
    Show-Status "Applying L2/L3 cache size registry tweak..."
    try {
        # Get L2 and L3 cache sizes in KB from CIM
        $cpuInfo = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop
        $l2CacheSize = $cpuInfo.L2CacheSize
        $l3CacheSize = $cpuInfo.L3CacheSize

        if ($l2CacheSize -and $l3CacheSize) {
            Show-Status "Detected L2: $($l2CacheSize)KB, L3: $($l3CacheSize)KB. Applying to registry."
            # These registry keys are protected, so we use the TrustedInstaller helper.
            # We inject the detected values directly into the command string.
            $commandToRun = @"
`$regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
Set-ItemProperty -Path `$regPath -Name 'SecondLevelDataCache' -Value $l2CacheSize -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path `$regPath -Name 'ThirdLevelDataCache' -Value $l3CacheSize -Type DWord -Force -ErrorAction SilentlyContinue
"@
            Invoke-CommandAsTrustedInstaller -CommandToRun $commandToRun
        }
    } catch {
        Show-Status "Could not apply L2/L3 cache tweak: $_" "Red"
    }

    Start-Service -Name "FontCache" -ErrorAction SilentlyContinue
    if (-not $IsPartOfBatch) {
        $completionMessage = "OS caches cleaned and L2/L3 cache tweak applied."
        Show-Status $completionMessage "Green"; Show-CompletionDialog $completionMessage; Enable-Buttons
    }
}

function Clear-RegistryTracking {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Clearing registry tracking & backups..."

    # 1. Disable registry access auditing to prevent logging to the Security event log.
    Show-Status "Disabling registry access auditing..."
    Invoke-Command "auditpol" "/set /subcategory:`"Registry`" /success:disable /failure:disable"

    # 2. Clear the idle registry backup folder (RegBack) and transaction logs.
    # These are periodic backups and transaction files for the main registry hives.
    # These folders are protected and require elevated permissions.
    $pathsToClean = @(
        "$env:SystemRoot\System32\config\RegBack",
        "$env:SystemRoot\System32\config" # To target the .LOG files
    )
    foreach ($path in $pathsToClean) {
        if (Test-Path $path) {
            Show-Status "Cleaning protected path: $path"
            $command = "Remove-Item -Path '$path\*.LOG*' -Recurse -Force -ErrorAction SilentlyContinue"
            Invoke-CommandAsTrustedInstaller -CommandToRun $command
        }
    }

    if (-not $IsPartOfBatch) {
        $completionMessage = "Registry tracking mechanisms disabled and backups cleared."
        Show-Status $completionMessage "Green"; Show-CompletionDialog $completionMessage; Enable-Buttons
    }
}

function Flush-StandbyCache {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Flushing system standby memory cache (Anti-Cheat Evasion)..."

    # This enhanced function uses direct NT kernel calls to aggressively clear memory caches,
    # which is more effective for anti-cheat evasion than the standard EmptyWorkingSet.
    $cSharpCode = @"
using System;
using System.Runtime.InteropServices;

public class NtMemoryApi {
    // Define the enum for memory list commands
    public enum SYSTEM_MEMORY_LIST_COMMAND {
        MemoryEmptyWorkingSets = 2,
        MemoryFlushModifiedList = 3,
        MemoryPurgeStandbyList = 4,
        MemoryPurgeAndResetStandbyList = 5
    }

    // Import the native function from ntdll.dll
    [DllImport("ntdll.dll")]
    public static extern int NtSetSystemInformation(int SystemInformationClass, ref SYSTEM_MEMORY_LIST_COMMAND SystemInformation, int SystemInformationLength);
}
"@
    if (-not ([System.Management.Automation.PSTypeName]'NtMemoryApi').Type) {
        Add-Type -TypeDefinition $cSharpCode
    }

    # Define the constant for SystemMemoryListInformation
    $SystemMemoryListInformation = 80

    # Commands to execute in sequence for a thorough flush
    $commands = @(
        [NtMemoryApi+SYSTEM_MEMORY_LIST_COMMAND]::MemoryPurgeStandbyList,
        [NtMemoryApi+SYSTEM_MEMORY_LIST_COMMAND]::MemoryFlushModifiedList,
        [NtMemoryApi+SYSTEM_MEMORY_LIST_COMMAND]::MemoryEmptyWorkingSets
    )

    foreach ($command in $commands) {
        Show-Status "Executing memory command: $command"
        [NtMemoryApi]::NtSetSystemInformation($SystemMemoryListInformation, [ref]$command, 4) | Out-Null
    }

    if (-not $IsPartOfBatch) { $completionMessage = "System standby memory cache flushed."; Show-Status $completionMessage "Green"; Show-CompletionDialog $completionMessage; Enable-Buttons }
}

function Optimize-PowerAndSleep {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Optimizing power and sleep settings..."

    # 1. Disable Hibernation to delete hiberfil.sys and save disk space
    Show-Status "Disabling hibernation (deletes hiberfil.sys)..."
    Invoke-Command "powercfg.exe" "-h off"

    # 2. Set Page File to be cleared at shutdown for enhanced privacy
    # This can slightly increase shutdown time.
    Show-Status "Setting page file to clear at shutdown (requires SYSTEM)..."
    $command = @"
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name "ClearPageFileAtShutdown" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
"@
    Invoke-CommandAsTrustedInstaller -CommandToRun $command

    # 3. Disable Fast Startup (which relies on hibernation) for cleaner shutdowns
    Show-Status "Disabling Fast Startup for cleaner shutdowns (requires SYSTEM)..."
    $command = @"
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name "HiberbootEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
"@
    Invoke-CommandAsTrustedInstaller -CommandToRun $command

    if (-not $IsPartOfBatch) {
        $completionMessage = "Power & sleep optimizations applied."
        Show-Status $completionMessage "Green"
        Show-CompletionDialog $completionMessage
        Enable-Buttons
    }
}

function Remove-BitsJobs {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Cleaning BITS (Background Intelligent Transfer Service) jobs..."

    # Stop the BITS service to ensure files can be deleted and the service reset.
    Stop-Service -Name "BITS" -Force -ErrorAction SilentlyContinue
    
    # Use bitsadmin to clear all jobs for all users. This is the most reliable method.
    # This command needs to run with elevated privileges, which the script should have.
    Invoke-Command "bitsadmin.exe" "/reset /allusers"

    # As a fallback/aggressive measure, also delete the queue files directly.
    # This path is also cleaned in Reset-DataUsage, but it's fine to be thorough.
    $bitsQueuePath = "$env:ALLUSERSPROFILE\Microsoft\Network\Downloader\*"
    if (Test-Path $bitsQueuePath) {
        Show-Status "Removing BITS queue files from $bitsQueuePath"
        Remove-Item -Path $bitsQueuePath -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Restart the BITS service.
    Start-Service -Name "BITS" -ErrorAction SilentlyContinue

    if (-not $IsPartOfBatch) {
        $completionMessage = "BITS jobs cleaned successfully."
        Show-Status $completionMessage "Green"
        Show-CompletionDialog $completionMessage
        Enable-Buttons
    }
}

function Remove-BamDamLogs {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Cleaning BAM/DAM activity logs (requires SYSTEM)..."

    # This function requires SYSTEM privileges to modify the service registry keys.
    $command = @"
`$ErrorActionPreference = 'SilentlyContinue'

# Stop the services to release registry key locks.
# DAM is 'Diagnostic Service Host' (DsmSvc), BAM is 'Background Tasks Infrastructure Service' (BrokerInfrastructure)
Write-Host "Stopping DAM (DsmSvc) and BAM (BrokerInfrastructure) services..."
Stop-Service -Name "DsmSvc" -Force
Stop-Service -Name "BrokerInfrastructure" -Force

# Delete and recreate the UserSettings keys which contain the execution logs for ALL users.
Write-Host "Deleting and recreating DAM UserSettings registry key..."
Remove-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\dam\UserSettings' -Recurse -Force
New-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\dam\UserSettings' -Force | Out-Null

Write-Host "Deleting and recreating BAM UserSettings registry key..."
Remove-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\bam\UserSettings' -Recurse -Force
New-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\bam\UserSettings' -Force | Out-Null

# Restart the services.
Write-Host "Restarting services..."
Start-Service -Name "BrokerInfrastructure"
Start-Service -Name "DsmSvc"
"@
    Invoke-CommandAsTrustedInstaller -CommandToRun $command

    if (-not $IsPartOfBatch) { $completionMessage = "BAM/DAM activity logs cleared."; Show-Status $completionMessage "Green"; Show-CompletionDialog $completionMessage; Enable-Buttons }
}

function Reset-AppRunTime {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Resetting all application runtime data..."

    # --- Part 1: Clean BAM/DAM activity logs (requires SYSTEM) ---
    Show-Status "Cleaning BAM/DAM activity logs..."
    $bamDamCommand = @"
`$ErrorActionPreference = 'SilentlyContinue'
Stop-Service -Name "DsmSvc" -Force
Stop-Service -Name "BrokerInfrastructure" -Force
Remove-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\dam\UserSettings' -Recurse -Force
New-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\dam\UserSettings' -Force | Out-Null
Remove-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\bam\UserSettings' -Recurse -Force
New-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\bam\UserSettings' -Force | Out-Null
Start-Service -Name "BrokerInfrastructure"
Start-Service -Name "DsmSvc"
"@
    Invoke-CommandAsTrustedInstaller -CommandToRun $bamDamCommand

    # --- Part 2: Reset SRUM database ---
    Show-Status "Resetting SRUM database (srudb.dat)..."
    $srumPath = "$env:SystemRoot\System32\sru\srudb.dat"
    if (Test-Path $srumPath) {
        Stop-Service -Name "DPS" -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $srumPath -Force -ErrorAction SilentlyContinue
        Start-Service -Name "DPS" -ErrorAction SilentlyContinue
    }

    if (-not $IsPartOfBatch) { $completionMessage = "Application runtime data has been reset."; Show-Status $completionMessage "Green"; Show-CompletionDialog $completionMessage; Enable-Buttons }
}

function Remove-SystemRestorePoints {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Deleting all system restore points..."

    # Stop the Volume Shadow Copy service before deleting
    Stop-Service -Name VSS -Force -ErrorAction SilentlyContinue

    # vssadmin requires elevation, which the script is already set to run with.
    Invoke-Command "vssadmin" "delete shadows /all /quiet"

    # Restart the service
    Start-Service -Name VSS -ErrorAction SilentlyContinue

    if (-not $IsPartOfBatch) {
        $completionMessage = "All system restore points have been deleted."
        Show-Status $completionMessage "Green"; Show-CompletionDialog $completionMessage; Enable-Buttons
    }
}

function Remove-WindowsSearchDeep {
    param([switch]$IsPartOfBatch)
    if (-not $IsPartOfBatch) { Disable-Buttons }
    Show-Status "Performing deep clean of Windows Search..."

    # This command block will run as SYSTEM to stop the service and delete the index.
    $command = @"
`$ErrorActionPreference = 'SilentlyContinue'

# Stop the Windows Search service
Write-Host "Stopping Windows Search service (WSearch)..."
Stop-Service -Name "WSearch" -Force

# The main search index database file and related files are in this folder.
`$searchPath = Join-Path -Path "`$env:ProgramData" -ChildPath "Microsoft\Search"

if (Test-Path `$searchPath) {
    Write-Host "Deleting Windows Search index folder: `$searchPath"
    Remove-Item -Path `$searchPath -Recurse -Force
}

# Restart the service. Windows will recreate the index folder and start re-indexing.
Write-Host "Starting Windows Search service..."
Start-Service -Name "WSearch"
"@
    Invoke-CommandAsTrustedInstaller -CommandToRun $command

    if (-not $IsPartOfBatch) {
        $completionMessage = "Windows Search deep clean complete. The index will be rebuilt in the background."
        Show-Status $completionMessage "Green"
        Show-CompletionDialog $completionMessage
        Enable-Buttons
    }
}
#endregion Cleaning Functions

#region GUI Definition

#region Theme Colors & Fonts
$theme_backgroundStart = [System.Drawing.Color]::FromArgb(5, 2, 8)      # Even Darker Purple/Black
$theme_backgroundEnd   = [System.Drawing.Color]::FromArgb(20, 10, 30)   # Darker Purple
$theme_accent          = [System.Drawing.Color]::FromArgb(118, 38, 158) # Darker, less saturated Purple
$theme_accent_hover    = [System.Drawing.Color]::FromArgb(98, 31, 130)  # Darker Accent for solid button hover
$theme_button_hover    = [System.Drawing.Color]::FromArgb(35, 10, 50)   # Darker background fill for buttons
$theme_text            = [System.Drawing.Color]::White
$theme_text_subtle     = [System.Drawing.Color]::FromArgb(160, 160, 160) # Light Gray

$titleFont = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$boldButtonFont = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$regularButtonFont = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Regular)
$labelFont = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Regular)
#endregion

# --- Variables for Draggable Window ---
$script:isDragging = $false
$script:dragStartPoint = New-Object System.Drawing.Point

$mainForm = New-Object System.Windows.Forms.Form
$mainForm.Text = 'OPTI$HIT Cleaner v1.0'
$mainForm.Size = New-Object System.Drawing.Size(500, 650)
$mainForm.StartPosition = 'CenterScreen'
$mainForm.FormBorderStyle = 'None' # Make the window borderless
$mainForm.MaximizeBox = $false

# Set the form icon for the taskbar and window corner
$formIconPath = ".\icon.ico"
if (Test-Path $formIconPath) {
    try {
        $mainForm.Icon = [System.Drawing.Icon]::new($formIconPath)
    }
    catch {
        # Silently fail if icon can't be loaded.
    }
}

# Add a handler for when the form is closing to clean up traces
$mainForm.Add_FormClosing({
    Remove-TracesOnExit
})

# Add logic to move the borderless main form
$mainForm.Add_MouseDown({
    param($src, $evt)
    # Ensure dragging doesn't happen when clicking on a control like a button
    if ($src.GetChildAtPoint($evt.Location) -eq $null -and $evt.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $script:isDragging = $true
        $script:dragStartPoint = $evt.Location
    }
})
$mainForm.Add_MouseMove({
    param($src, $evt)
    if ($script:isDragging) {
        $newLocation = New-Object System.Drawing.Point(
            ($evt.X - $script:dragStartPoint.X + $src.Left),
            ($evt.Y - $script:dragStartPoint.Y + $src.Top)
        )
        $src.Location = $newLocation
    }
})
$mainForm.Add_MouseUp({
    param($src, $evt)
    if ($evt.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $script:isDragging = $false
    }
})

# Handle the Paint event to draw a gradient background from black to dark purple
$mainForm.Add_Paint({
    param($src, $evt)
    $graphics = $evt.Graphics
    # Use theme colors for gradient
    $gradientRect = $src.ClientRectangle
    $startColor = $theme_backgroundStart
    $endColor = $theme_backgroundEnd
    $gradientBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($gradientRect, $startColor, $endColor, [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
    $graphics.FillRectangle($gradientBrush, $gradientRect)
    $gradientBrush.Dispose()

    # Draw a magenta border around the form
    $borderPen = New-Object System.Drawing.Pen($theme_accent, 2)
    $borderPen.Alignment = [System.Drawing.Drawing2D.PenAlignment]::Inset
    $graphics.DrawRectangle($borderPen, $src.ClientRectangle)
    $borderPen.Dispose()
})

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = 'OPTI$HIT CLEANER'
$titleLabel.Font = $titleFont
$titleLabel.ForeColor = $theme_text
$titleLabel.BackColor = [System.Drawing.Color]::Transparent
$titleLabel.AutoSize = $true
$titleLabel.Location = New-Object System.Drawing.Point(10, 10)
$mainForm.Controls.Add($titleLabel) 

$buttonYStart = 60
$script:currentPage = 1
$script:totalPages = 2
$buttonHeight = 30
$buttonWidth = 200
$col1X = 40
$col2X = 260
$buttonYMargin = 10 # Increase buttonYMargin for more gap between buttons

# --- Custom Progress Bar ---
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Size = New-Object System.Drawing.Size(500, 15)
$progressBar.Visible = $false
$progressBar.Style = 'Blocks' # Use Blocks style for custom drawing
$progressBar.Step = 1
$progressBar.Dock = 'Bottom'

# Add custom paint event to color the progress bar
$progressBar.Add_Paint({
    param($src, $e)
    # Turn off visual styles for this control to allow custom drawing
    [System.Windows.Forms.Application]::VisualStyleState = [System.Windows.Forms.VisualStyles.VisualStyleState]::NoneEnabled

    $rect = $e.ClipRectangle
    $progressWidth = [int](($src.Value / $src.Maximum) * $rect.Width)
    $progressRect = New-Object System.Drawing.Rectangle(0, 0, $progressWidth, $rect.Height)

    # Use theme colors for the progress bar
    $e.Graphics.FillRectangle([System.Drawing.Brushes]::Transparent, $rect) # Clear background
    $e.Graphics.FillRectangle((New-Object System.Drawing.SolidBrush $theme_accent), $progressRect) # Draw progress
})

$mainForm.Controls.Add($progressBar)

$statusBar = New-Object System.Windows.Forms.Label
$statusBar.Text = "Status: Ready. Select an option."
$statusBar.Dock = 'Bottom'
$statusBar.TextAlign = 'MiddleLeft'
$statusBar.Font = $labelFont
$statusBar.BackColor = $theme_accent
$statusBar.ForeColor = $theme_text
$statusBar.Padding = New-Object System.Windows.Forms.Padding(5, 0, 0, 0)
$mainForm.Controls.Add($statusBar)

#region Panels for Pagination
$page1Panel = New-Object System.Windows.Forms.Panel
$page1Panel.Location = New-Object System.Drawing.Point(0, 40)
$page1Panel.Size = New-Object System.Drawing.Size(500, 410)
$page1Panel.BackColor = [System.Drawing.Color]::Transparent

$page2Panel = New-Object System.Windows.Forms.Panel
$page2Panel.Location = $page1Panel.Location
$page2Panel.Size = $page1Panel.Size
$page2Panel.BackColor = [System.Drawing.Color]::Transparent
$page2Panel.Visible = $false # Hide page 2 initially

$page3Panel = New-Object System.Windows.Forms.Panel
$page3Panel.Location = $page1Panel.Location
$page3Panel.Size = $page1Panel.Size
$page3Panel.BackColor = [System.Drawing.Color]::Transparent
$page3Panel.Visible = $false # Hide page 3 initially

$buttons = @(
    @{ Name = 'Clear DNS Cache';  Action = { Clear-DnsCache } },
    @{ Name = 'FiveM Traces';     Action = { Remove-FiveMTraces } },
    @{ Name = 'Registry Traces';  Action = { Remove-RegistryTraces } },
    @{ Name = 'Recent Apps';      Action = { Remove-RecentApps } },
    @{ Name = 'Temp Files';       Action = { Remove-TempFiles } },
    @{ Name = 'Browsing Data';    Action = { Remove-BrowsingData } },
    @{ Name = 'USN Journal';      Action = { Remove-UsnJournal } },
    @{ Name = 'Delete Shadows';   Action = { Remove-Shadows } },
    @{ Name = 'USB Plug History'; Action = { Remove-UsbHistory } },
    @{ Name = 'USB Plug (Deep)';  Action = { Remove-AllUsbHistory } },
    @{ Name = 'Print Spooler';    Action = { Remove-PrintSpooler } },
    @{ Name = 'Clean Powershell'; Action = { Remove-PowershellHistory } },
    @{ Name = 'Cipher Cleanup';   Action = { Start-CipherCleanup } },
    @{ Name = 'Event Logs';       Action = { Clear-EventLogs } },
    @{ Name = 'Clean NVIDIA';     Action = { Remove-NvidiaCache } },
    @{ Name = 'Clean AMD';        Action = { Remove-AmdCache } },
    @{ Name = 'ShimCache';        Action = { Remove-ShimCache } },
    @{ Name = 'AmCache';          Action = { Remove-Amcache } },
    @{ Name = 'Defender History'; Action = { Remove-DefenderHistory } },
    @{ Name = 'WMI Repository';   Action = { Remove-WmiRepository } },
    @{ Name = 'Steam Accounts';   Action = { Remove-SteamAccounts } }, # This is the new button
    @{ Name = 'Epic Games Cleanup'; Action = { Remove-EpicGames } }, # This is the new button
    @{ Name = 'Rockstar Logins';  Action = { Remove-RockstarCache } },
    @{ Name = 'Discord Cache';    Action = { Remove-DiscordCache } },
    @{ Name = 'Reset Data Usage'; Action = { Reset-DataUsage } },
    @{ Name = 'Clean ImGui';      Action = { Remove-ImGuiIniFiles } },
    @{ Name = 'Clean Run History';Action = { Remove-RunHistoryDeep } },
    @{ Name = 'Clean Form History';Action = { Remove-FormHistory } },
    @{ Name = 'OSForensics Logs'; Action = { Remove-OSForensicsLogs } },
    @{ Name = 'NirSoft Traces';   Action = { Remove-NirSoftTraces } },
    @{ Name = 'Deep Clean Xbox';  Action = { Remove-XboxDeep } },
    @{ Name = 'Clear Process Memory'; Action = { Remove-ProcessStrings -RestartExplorer } },
    @{ Name = 'DirectX Cache';    Action = { Remove-DirectXCache } },
    @{ Name = 'CPU Caches';       Action = { Remove-CpuCaches } },
    @{ Name = 'Flush Standby Cache'; Action = { Flush-StandbyCache } },
    @{ Name = 'Optimize Power/Sleep'; Action = { Optimize-PowerAndSleep } },
    @{ Name = 'Clear Registry Tracking'; Action = { Clear-RegistryTracking } },
    # Add the new BITS cleaner button
    @{ Name = 'Clean BITS Jobs'; Action = { Remove-BitsJobs } },
    # Add the new high-risk button
    @{ Name = 'Forensic Bypass'; Action = { Invoke-ForensicBypass } }
    @{ Name = 'Clean BAM/DAM Logs'; Action = { Remove-BamDamLogs } },
    @{ Name = 'Anti-Forensics'; Action = { Invoke-AntiForensics } },
    @{ Name = 'Reset App Runtime'; Action = { Reset-AppRunTime } },
    @{ Name = 'System Restore Points'; Action = { Remove-SystemRestorePoints } },
    @{ Name = 'Disable Telemetry (Deep)'; Action = { Disable-TelemetryDeep } },
    @{ Name = 'Deep Clean Search'; Action = { Remove-WindowsSearchDeep } },
    @{ Name = 'Flush Memory (svchost)'; Action = { Flush-StandbyCache } }
);
 
$i = 0
foreach ($buttonInfo in $buttons) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $buttonInfo.Name
    $button.Font = $regularButtonFont
    $button.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $button.BackColor = $theme_button_hover
    $button.ForeColor = $theme_text
    $button.FlatStyle = 'Flat'
    $button.FlatAppearance.BorderSize = 0
    $button.FlatAppearance.MouseOverBackColor = $theme_accent_hover
    $button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::Transparent
    $button.Add_MouseEnter({ $this.BackColor = $theme_accent_hover })
    $button.Add_MouseLeave({ $this.BackColor = $theme_button_hover })
    $button.Add_Click($buttonInfo.Action)

    # Pagination logic: 20 buttons per page
    $currentPagePanel = if ($i -lt 20) { $page1Panel } elseif ($i -lt 40) { $page2Panel } else { $page3Panel }
    $buttonIndexOnPage = $i % 20
    $rowOnPage = [math]::Floor($buttonIndexOnPage / 2)
    $colOnPage = $buttonIndexOnPage % 2
    $xPos = if ($colOnPage -eq 0) { $col1X } else { $col2X }
    $yPos = ($buttonYStart - 50) + ($rowOnPage * ($buttonHeight + $buttonYMargin))
    $button.Location = New-Object System.Drawing.Point($xPos, $yPos)
    $button.Region = [System.Drawing.Region]::FromHrgn([Win32]::CreateRoundRectRgn(0, 0, $button.Width, $button.Height, 15, 15))
    $currentPagePanel.Controls.Add($button)
    $i++
}
# Update total pages based on the number of buttons
$script:totalPages = [math]::Ceiling($buttons.Count / 20)

$mainForm.Controls.Add($page1Panel)
$mainForm.Controls.Add($page2Panel)

#region Navigation Buttons
$nextButton = New-Object System.Windows.Forms.Button
$nextButton.Text = '>'
$nextButton.Font = $boldButtonFont
$nextButton.Size = New-Object System.Drawing.Size(40, 35)
$nextButton.Location = New-Object System.Drawing.Point(320, 575)
$nextButton.BackColor = [System.Drawing.Color]::Transparent
$nextButton.ForeColor = $theme_text
$nextButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$nextButton.FlatAppearance.BorderSize = 0
$nextButton.FlatAppearance.MouseOverBackColor = $theme_button_hover
$nextButton.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::Transparent

$nextButton.Add_Paint({
    param($src, $evt)
    $g = $evt.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $pen = New-Object System.Drawing.Pen($theme_text, 2)
    # Draw rectangle slightly inside to account for pen width
    $g.DrawRectangle($pen, 1, 1, $sender.Width - 2, $sender.Height - 2)
    $pen.Dispose()
})

$prevButton = New-Object System.Windows.Forms.Button
$prevButton.Text = '<'
$prevButton.Font = $boldButtonFont
$prevButton.Size = New-Object System.Drawing.Size(40, 35)
$prevButton.Location = New-Object System.Drawing.Point(140, 575)
$prevButton.BackColor = [System.Drawing.Color]::Transparent
$prevButton.ForeColor = $theme_text
$prevButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$prevButton.FlatAppearance.BorderSize = 0
$prevButton.FlatAppearance.MouseOverBackColor = $theme_button_hover
$prevButton.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::Transparent
$prevButton.Visible = $false # Initially hidden

$prevButton.Add_Paint({
    param($src, $evt)
    $g = $evt.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $pen = New-Object System.Drawing.Pen($theme_text, 2)
    # Draw rectangle slightly inside to account for pen width
    $g.DrawRectangle($pen, 1, 1, $sender.Width - 2, $sender.Height - 2)
    $pen.Dispose()
})

$nextButton.Add_Click({
    $script:currentPage++
    Update-PageVisibility
})

$prevButton.Add_Click({
    $script:currentPage--
    Update-PageVisibility
})
#endregion

$applyAllButton = New-Object System.Windows.Forms.Button
$applyAllButton.Text = 'Apply All (Recommended)'
$applyAllButton.Font = $boldButtonFont
$applyAllButton.Size = New-Object System.Drawing.Size(420, 35)
$applyAllButton.Location = New-Object System.Drawing.Point(40, 470)
$applyAllButton.BackColor = $theme_accent
$applyAllButton.ForeColor = $theme_text
$applyAllButton.FlatStyle = 'Flat'
$applyAllButton.FlatAppearance.BorderSize = 0
$applyAllButton.FlatAppearance.MouseOverBackColor = $theme_accent_hover
$applyAllButton.Add_Click({ Remove-All })
$mainForm.Controls.Add($applyAllButton)

$applyAllButton.Region = [System.Drawing.Region]::FromHrgn([Win32]::CreateRoundRectRgn(0, 0, $applyAllButton.Width, $applyAllButton.Height, 20, 20))

$exitButton = New-Object System.Windows.Forms.Button
$exitButton.Text = 'Exit'
$exitButton.Font = $boldButtonFont
$exitButton.Size = New-Object System.Drawing.Size(420, 35)
$exitButton.Location = New-Object System.Drawing.Point(40, 515)
$exitButton.BackColor = $theme_button_hover
$exitButton.ForeColor = $theme_text
$exitButton.FlatStyle = 'Flat'
$exitButton.FlatAppearance.BorderSize = 0
$exitButton.FlatAppearance.MouseOverBackColor = $theme_accent_hover
$exitButton.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::Transparent
$exitButton.Add_Click({ $mainForm.Close() })
$exitButton.Add_MouseEnter({
    $this.BackColor = $theme_accent_hover
})
$exitButton.Add_MouseLeave({
    $this.BackColor = $theme_button_hover
})
$mainForm.Controls.Add($exitButton)

$exitButton.Region = [System.Drawing.Region]::FromHrgn([Win32]::CreateRoundRectRgn(0, 0, $exitButton.Width, $exitButton.Height, 20, 20))

$brandingLabel = New-Object System.Windows.Forms.Label
$brandingLabel.Text = "by OPTISHIT"
$brandingLabel.AutoSize = $true
$brandingLabel.ForeColor = $theme_text_subtle
$brandingLabel.BackColor = [System.Drawing.Color]::Transparent
$brandingLabel.Location = New-Object System.Drawing.Point(215, 585)
$mainForm.Controls.Add($brandingLabel)
$mainForm.Controls.Add($nextButton)
$mainForm.Controls.Add($prevButton)
$mainForm.Controls.Add($page3Panel)


#endregion GUI Definition

#region Main Execution

[System.Windows.Forms.Application]::EnableVisualStyles()

# Run the password check before showing the main form.
Show-PasswordPrompt

# Clean up traces of previous runs on start
Remove-TracesOnExit

# Show the main form directly
Show-Status "Ready. Run as Administrator."
$mainForm.ShowDialog()

#endregion Main Execution
