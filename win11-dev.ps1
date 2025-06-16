$ScriptName = 'Windows 11 Developer Edition'
$ScriptVersion = '24.7.4.4'
Write-Host -ForegroundColor Green "$ScriptName $ScriptVersion"

#=======================================================================
#   OSDCLOUD Definitions
#=======================================================================
$Product = (Get-MyComputerProduct)
$Model = (Get-MyComputerModel)
$Manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
$OSVersion = 'Windows 11' #Used to Determine Driver Pack
$OSReleaseID = '24H2' #Used to Determine Driver Pack
$OSName = 'Windows 11 24H2 x64'
$OSEdition = 'Pro'
$OSActivation = 'Retail'
$OSLanguage = 'en-us'

#=======================================================================
#   OSDCLOUD VARS
#=======================================================================
$Global:MyOSDCloud = [ordered]@{
    Restart               = [bool]$false
    RecoveryPartition     = [bool]$true
    OEMActivation         = [bool]$true 
    WindowsUpdate         = [bool]$true #temporarily disabled same thing almost 10 minutes
    MSCatalogFirmware     = [bool]$true #temporarily disabled no impact
    WindowsUpdateDrivers  = [bool]$true #temporarily disabled this is causing long delays on the getting ready screen before the oobe (almost 10 minutes)
    WindowsDefenderUpdate = [bool]$true #temporarily disabled same thing almost 10 minutes
    SetTimeZone           = [bool]$true
    SkipClearDisk         = [bool]$false
    ClearDiskConfirm      = [bool]$false
    ShutdownSetupComplete = [bool]$false
    SyncMSUpCatDriverUSB  = [bool]$true
    CheckSHA1             = [bool]$true
}

#for a more complete rollout of the OSDCloud process, you can enable the following options: WindowsUpdate, MSCatalogFirmware, WindowsUpdateDrivers, WindowsDefenderUpdate, SyncMSUpCatDriverUSB

#=======================================================================
#   LOCAL DRIVE LETTERS
#=======================================================================
function Get-WinPEDrive {
    $WinPEDrive = (Get-WmiObject Win32_LogicalDisk | Where-Object { $_.VolumeName -eq 'WINPE' }).DeviceID
    write-host "Current WINPE drive is: $WinPEDrive"
    return $WinPEDrive
}
function Get-OSDCloudDrive {
    $OSDCloudDrive = (Get-WmiObject Win32_LogicalDisk | Where-Object { $_.VolumeName -eq 'OSDCloudUSB' }).DeviceID
    write-host "Current OSDCLOUD Drive is: $OSDCloudDrive"
    return $OSDCloudDrive
}

Read-Host -Prompt "Press Enter to continue"

#=======================================================================
#   OSDCLOUD Image
#=======================================================================
$uselocalimage = $true
$Windowsversion = "$OSVersion $OSReleaseID"
$OSDCloudDrive = Get-OSDCloudDrive
Write-Host -ForegroundColor Green -BackgroundColor Black "UseLocalImage is set to: $uselocalimage"
#dynamically find the latest version based on the variables set in the beginning of the script
if ($uselocalimage -eq $true) {
    # Find the latest month WIM file
    $months = @("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "okt", "nov", "dec")
    $wimlist = Get-ChildItem -Path "$OSDCloudDrive\OSDCloud\OS\" -Filter "*.wim" -Recurse
    write-host "Available wimfiles: $wimlist"
    $wimFiles = Get-ChildItem -Path "$OSDCloudDrive\OSDCloud\OS\" -Filter "*.wim" -Recurse | Where-Object { $_.Name -match "$Windowsversion" }
    $latestMonth = $months | Where-Object { $wimFiles.Name -match $_ } | Select-Object -Last 1

    if ($latestMonth) {
        $WIMName = "$Windowsversion - $latestMonth.wim"
        Write-Host -ForegroundColor Green -BackgroundColor Black "Latest WIM file found: $WIMName This WimFile will be used for the installation"
    }
    else {
        Write-Host -ForegroundColor Red -BackgroundColor Black "No WIM files found for $Windowsversion using esd as backup."
        Write-Host -ForegroundColor Red -BackgroundColor Black "PLEASE ADD THE WIM FILE TO THE OSDCLOUD USB DRIVE TO SURPRESS THIS MESSAGE"
        $uselocalimage = $false
        Start-Sleep -Seconds 10
    }
}

Read-Host -Prompt "Press Enter to continue"

if ($uselocalimage -eq $true) {
    $ImageFileItem = Find-OSDCloudFile -Name $WIMName  -Path "\OSDCloud\OS\"
    if ($ImageFileItem) {
        write-host "Variable uselocalimage is set to true. The installer will try to find and use the wim file called: $WIMName"
        $ImageFileItem = $ImageFileItem | Where-Object { $_.FullName -notlike "C*" } | Where-Object { $_.FullName -notlike "X*" } | Select-Object -First 1
        if ($ImageFileItem) {
            $ImageFileName = Split-Path -Path $ImageFileItem.FullName -Leaf
            $ImageFileFullName = $ImageFileItem.FullName
            
            $Global:MyOSDCloud.ImageFileItem = $ImageFileItem
            $Global:MyOSDCloud.ImageFileName = $ImageFileName
            $Global:MyOSDCloud.ImageFileFullName = $ImageFileFullName
            $Global:MyOSDCloud.OSImageIndex = 6
        }
    }
}

Read-Host -Prompt "Press Enter to continue"

#=======================================================================
#   Specific Driver Pack
#=======================================================================
$DriverPack = Get-OSDCloudDriverPack -Product $Product -OSVersion $OSVersion -OSReleaseID $OSReleaseID

if ($DriverPack) {
    $Global:MyOSDCloud.DriverPackName = $DriverPack.Name
}
$UseHPIA = $true #disable this for faster deployment, but less up-to-date
if ($Manufacturer -match "HP" -and $UseHPIA -eq $true) {
    #$Global:MyOSDCloud.DevMode = [bool]$True
    $Global:MyOSDCloud.HPTPMUpdate = [bool]$True
    { $Global:MyOSDCloud.HPIAALL = [bool]$true }
    $Global:MyOSDCloud.HPBIOSUpdate = [bool]$true
    $Global:MyOSDCloud.HPCMSLDriverPackLatest = [bool]$true
}

if ($Manufacturer -match "HP") {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope AllUsers -Force 
    Install-Module -Name PowerShellGet -Scope CurrentUser -AllowClobber -Force
    Install-Module -Name HPCMSL -Force -Scope AllUsers -SkipPublisherCheck
}

Read-Host -Prompt "Press Enter to continue"

#=======================================================================
#   Write OSDCloud VARS to Console
#=======================================================================
Write-Output $Global:MyOSDCloud

#=======================================================================
#   Update OSDCloud modules
#=======================================================================
$ModulePath = (Get-ChildItem -Path "$($Env:ProgramFiles)\WindowsPowerShell\Modules\osd" | Where-Object {$_.Attributes -match "Directory"} | select -Last 1).fullname
import-module "$ModulePath\OSD.psd1" -Force

#=======================================================================
#   Start OSDCloud installation
#=======================================================================
Write-Host "Starting OSDCloud" -ForegroundColor Green
write-host "Start-OSDCloud -OSName $OSName -OSEdition $OSEdition -OSActivation $OSActivation -OSLanguage $OSLanguage"
Read-Host -Prompt "Press Enter to continue"

Start-OSDCloud -OSName $OSName -OSEdition $OSEdition -OSActivation $OSActivation -OSLanguage $OSLanguage

Read-Host -Prompt "Press Enter to continue"

write-host "OSDCloud Process Complete, Running Custom Actions From Script Before Reboot" -ForegroundColor Green

#=======================================================================
#   REBOOT DEVICE
#=======================================================================
Write-Host  -ForegroundColor Green "Restarting now!"
Restart-Computer -Force

Read-Host -Prompt "Press Enter to continue"