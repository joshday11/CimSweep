﻿function Get-CSRegistryAutoStart {
<#
.SYNOPSIS

List installed autostart execution points present in the registry.

Author: Matthew Graeber (@mattifestation)
License: BSD 3-Clause

.DESCRIPTION

Get-CSRegistryAutoStart lists autorun points present in the registry locally or remotely.

Get-CSRegistryAutoStart was heavily influenced by the great PowerShell autoruns function written by Emin Atac (@p0w3rsh3ll) - https://github.com/p0w3rsh3ll/AutoRuns. Emin's version is ideal for use locally and when PowerShell remoting is enabled. Get-CSRegistryAutoStart can retrieve autoruns information remotely from systems regardless of the presense of PowerShell.

Each switch argument in Get-CSRegistryAutoStart represents the corresponding tab in autoruns.exe.

.PARAMETER Logon

Retrieve logon artifacts

.PARAMETER LSAProviders

Retrieve LSA provider artifacts

.PARAMETER ImageHijacks

Retrieve image hijack artifacts

.PARAMETER AppInit

Retrieve appinit artifacts

.PARAMETER KnownDLLs

Retrieve KnownDLL artifacts

.PARAMETER Winlogon

Retrieve winlogon artifacts

.PARAMETER PrintMonitors

Retrieve print monitor artifacts

.PARAMETER NetworkProviders

Retrieve network provider artifacts

.PARAMETER BootExecute

Retrieve boot execute artifacts

.PARAMETER NoProgressBar

Do not display a progress bar. This parameter is designed to be used with wrapper functions.

.PARAMETER CimSession

Specifies the CIM session to use for this cmdlet. Enter a variable that contains the CIM session or a command that creates or gets the CIM session, such as the New-CimSession or Get-CimSession cmdlets. For more information, see about_CimSessions.

.PARAMETER OperationTimeoutSec

Specifies the amount of time that the cmdlet waits for a response from the computer.

By default, the value of this parameter is 0, which means that the cmdlet uses the default timeout value for the server.

If the OperationTimeoutSec parameter is set to a value less than the robust connection retry timeout of 3 minutes, network failures that last more than the value of the OperationTimeoutSec parameter are not recoverable, because the operation on the server times out before the client can reconnect.

.EXAMPLE

Get-CSRegistryAutoStart

Performs all supported autoruns entry category checks.

.EXAMPLE

Get-CSRegistryAutoStart -Logon -LSAProviders

Performs specific autoruns entry category checks.

.OUTPUTS

CimSweep.AutoRunEntry

Outputs objects representing autoruns entries similar to the output of Sysinternals Autoruns.
#>

    [CmdletBinding()]
    [OutputType('CimSweep.AutoRunEntry')]
    param(
        [Parameter(ParameterSetName = 'SpecificCheck')]
        [Switch]
        $Logon,

        [Parameter(ParameterSetName = 'SpecificCheck')]
        [Switch]
        $LSAProviders,

        [Parameter(ParameterSetName = 'SpecificCheck')]
        [Switch]
        $ImageHijacks,

        [Parameter(ParameterSetName = 'SpecificCheck')]
        [Switch]
        $AppInit,

        [Parameter(ParameterSetName = 'SpecificCheck')]
        [Switch]
        $KnownDLLs,

        [Parameter(ParameterSetName = 'SpecificCheck')]
        [Switch]
        $Winlogon,

        [Parameter(ParameterSetName = 'SpecificCheck')]
        [Switch]
        $PrintMonitors,

        [Parameter(ParameterSetName = 'SpecificCheck')]
        [Switch]
        $NetworkProviders,

        [Parameter(ParameterSetName = 'SpecificCheck')]
        [Switch]
        $BootExecute,

        [Switch]
        $NoProgressBar,

        [Alias('Session')]
        [ValidateNotNullOrEmpty()]
        [Microsoft.Management.Infrastructure.CimSession[]]
        $CimSession,

        [UInt32]
        [Alias('OT')]
        $OperationTimeoutSec
    )

    BEGIN {
        # If a CIM session is not provided, trick the function into thinking there is one.
        if (-not $PSBoundParameters['CimSession']) {
            $CimSession = ''
            $CIMSessionCount = 1
        } else {
            $CIMSessionCount = $CimSession.Count
        }

        $CurrentCIMSession = 0

        $Timeout = @{}
        if ($PSBoundParameters['OperationTimeoutSec']) { $Timeout['OperationTimeoutSec'] = $OperationTimeoutSec }

        $ParamCopy = $PSBoundParameters
        $null = $ParamCopy.Remove('CimSession')
        $null = $ParamCopy.Remove('NoProgressBar')
        $null = $ParamCopy.Remove('OperationTimeoutSec')

        # Count the number of options provided for use of displaying a progress bar
        $AutoRunOptionCount = $ParamCopy.Keys.Count

        # All checks want to be performed.
        # There is likely a better way of obtaining the number of params in the 'SpecificCheck' param set
        if (-not $AutoRunOptionCount) { $AutoRunOptionCount = 9 }

        # Helper function that maps a registry autorun artifact roughly to that of autoruns.exe output.
        # Ignore PsScriptAnalyzer rule for this verb name. It is a helper function that doesn't
        # modify system state.
        filter New-AutoRunsEntry {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
            Param (
                [Parameter(Position = 0, ValueFromPipelineByPropertyName = $True)]
                [String]
                $Hive,

                [Parameter(Position = 1, ValueFromPipelineByPropertyName = $True)]
                [String]
                $SubKey,

                [Parameter(Position = 2, ValueFromPipelineByPropertyName = $True)]
                [Alias('ValueName')]
                [String]
                $AutoRunEntry,

                [Parameter(Position = 3, ValueFromPipelineByPropertyName = $True)]
                [Alias('ValueContent')]
                [String]
                $ImagePath,

                [Parameter(Position = 4, Mandatory = $True)]
                [String]
                $Category,

                [Parameter(Position = 5, ValueFromPipelineByPropertyName = $True)]
                [String]
                $PSComputerName,

                [Parameter(ValueFromPipelineByPropertyName = $True)]
                [Alias('Session')]
                [Microsoft.Management.Infrastructure.CimSession]
                $CimSession
            )

            $ObjectProperties = [Ordered] @{
                PSTypeName = 'CimSweep.AutoRunEntry'
                Path = "$($Hive)\$($SubKey)"
                AutoRunEntry = $AutoRunEntry
                ImagePath = $ImagePath
                Category = $Category
            }

            $DefaultProperties = 'Path', 'AutoRunEntry', 'ImagePath', 'Category' -as [Type] 'Collections.Generic.List[String]'

            if ($PSComputerName) {
                $ObjectProperties['PSComputerName'] = $PSComputerName
                $DefaultProperties.Add('PSComputerName')
            } else {
                $ObjectProperties['PSComputerName'] = $null
            }

            if ($Session.Id) { $ObjectProperties['CimSession'] = $Session }

            $AutoRunsEntry = [PSCustomObject] $ObjectProperties

            Set-DefaultDisplayProperty -InputObject $AutoRunsEntry -PropertyNames $DefaultProperties

            $AutoRunsEntry
        }
    }

    PROCESS {
        foreach ($Session in $CimSession) {
            $CurrentAutorunCount = 0

            $ComputerName = $Session.ComputerName
            if (-not $Session.ComputerName) { $ComputerName = 'localhost' }

            if (-not $PSBoundParameters['NoProgressBar']) {
                # Display a progress activity for each CIM session
                Write-Progress -Id 1 -Activity 'CimSweep - Registry autoruns sweep' -Status "($($CurrentCIMSession+1)/$($CIMSessionCount)) Current computer: $ComputerName" -PercentComplete (($CurrentCIMSession / $CIMSessionCount) * 100)
                $CurrentCIMSession++
            }

            $CommonArgs = @{}

            if ($Session.Id) { $CommonArgs['CimSession'] = $Session }

            # Get the SIDS for each user in the registry
            $HKUSIDs = Get-HKUSID @CommonArgs @Timeout

            if (($PSCmdlet.ParameterSetName -ne 'SpecificCheck') -or $PSBoundParameters['Logon']) {
                $Category = 'Logon'

                if (-not $PSBoundParameters['NoProgressBar']) {
                    Write-Progress -Id 2 -ParentId 1 -Activity "   ($($CurrentAutorunCount+1)/$($AutoRunOptionCount)) Current autoruns type:" -Status $Category -PercentComplete (($CurrentAutorunCount / $AutoRunOptionCount) * 100)
                    $CurrentAutorunCount++
                }

                Get-CSRegistryValue -Hive HKLM -SubKey 'SYSTEM\CurrentControlSet\Control\Terminal Server\Wds\rdpwd' -ValueName StartupPrograms @CommonArgs @Timeout |
                    New-AutoRunsEntry -Category $Category

                Get-CSRegistryValue -Hive HKLM -SubKey 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ValueNameOnly @CommonArgs @Timeout |
                    Where-Object { ('VmApplet', 'Userinit', 'Shell', 'TaskMan', 'AppSetup') -contains $_.ValueName } | ForEach-Object {
                        $_ | Get-CSRegistryValue | New-AutoRunsEntry -Category $Category
                    }

                # Todo: implement on domain-joined system
                <#
                'Startup', 'Shutdown', 'Logon', 'Logoff' | ForEach-Object {
                    Get-CSRegistryKey -Hive HKLM -SubKey 'SOFTWARE\Policies\Microsoft\Windows\System\Scripts'
                }
                #>

                $GPExtensionKey = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\GPExtensions'
                Get-CSRegistryKey -Hive HKLM -SubKey $GPExtensionKey @CommonArgs @Timeout |
                    Get-CSRegistryValue -ValueName DllName @Timeout |
                        ForEach-Object { $_ | New-AutoRunsEntry -SubKey $GPExtensionKey -AutoRunEntry $_.Subkey.Split('\')[-1] -Category $Category }

                $AlternateShell = Get-CSRegistryValue -Hive HKLM -SubKey 'SYSTEM\CurrentControlSet\Control\SafeBoot' -ValueName AlternateShell @CommonArgs @Timeout

                if ($AlternateShell) { $AlternateShell | New-AutoRunsEntry -AutoRunEntry $AlternateShell.ValueContent -Category $Category }

                $AutoStartPaths = @(
                    'SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
                    'SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
                    'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
                    'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce'
                )

                foreach ($AutoStartPath in $AutoStartPaths) {
                    Get-CSRegistryValue -Hive HKLM -SubKey $AutoStartPath @CommonArgs @Timeout |
                        New-AutoRunsEntry -Category $Category

                    # Iterate over each local user hive
                    foreach ($SID in $HKUSIDs) {
                        Get-CSRegistryValue -Hive HKU -SubKey "$SID\$AutoStartPath" @CommonArgs @Timeout |
                            New-AutoRunsEntry -Category $Category
                    }
                }

                $null, 'Wow6432Node\' | ForEach-Object {
                    $InstalledComponents = "SOFTWARE\$($_)Microsoft\Active Setup\Installed Components"
                    Get-CSRegistryKey -Hive HKLM -SubKey $InstalledComponents @CommonArgs @Timeout
                } | Get-CSRegistryValue -ValueName StubPath @Timeout | ForEach-Object {
                    $AutoRunEntry = $_ | Get-CSRegistryValue -ValueName '' -ValueType REG_SZ @Timeout

                    if ($AutoRunEntry.ValueContent) { $AutoRunEntryName = $AutoRunEntry.ValueContent } else { $AutoRunEntryName = 'n/a' }

                    $_ | New-AutoRunsEntry -SubKey $InstalledComponents -AutoRunEntry $AutoRunEntryName -Category $Category
                }

                $IconLib = Get-CSRegistryValue -Hive HKLM -SubKey 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows' -ValueName IconServiceLib @CommonArgs @Timeout

                if ($IconLib) { $IconLib | New-AutoRunsEntry -SubKey "$($IconLib.SubKey)\$($IconLib.ValueName)" -AutoRunEntry $IconLib.ValueContent -Category $Category }
            }

            if (($PSCmdlet.ParameterSetName -ne 'SpecificCheck') -or $PSBoundParameters['BootExecute']) {
                $Category = 'BootExecute'

                if (-not $PSBoundParameters['NoProgressBar']) {
                    Write-Progress -Id 2 -ParentId 1 -Activity "   ($($CurrentAutorunCount+1)/$($AutoRunOptionCount)) Current autoruns type:" -Status $Category -PercentComplete (($CurrentAutorunCount / $AutoRunOptionCount) * 100)
                    $CurrentAutorunCount++
                }

                Get-CSRegistryValue -Hive HKLM -SubKey 'SYSTEM\CurrentControlSet\Control\Session Manager' -ValueNameOnly @CommonArgs @Timeout |
                    Where-Object { ('BootExecute','SetupExecute','Execute','S0InitialCommand') -contains $_.ValueName } | ForEach-Object {
                        $_ | Get-CSRegistryValue @Timeout | Where-Object { $_.ValueContent.Count } |
                            ForEach-Object { $_ | New-AutoRunsEntry -ImagePath "$($_.ValueContent)" -Category $Category }
                    }

                Get-CSRegistryValue -Hive HKLM -SubKey 'SYSTEM\CurrentControlSet\Control' -ValueName ServiceControlManagerExtension @CommonArgs @Timeout |
                    New-AutoRunsEntry -AutoRunEntry ServiceControlManagerExtension -Category $Category
            }

            if (($PSCmdlet.ParameterSetName -ne 'SpecificCheck') -or $PSBoundParameters['PrintMonitors']) {
                $Category = 'PrintMonitors'

                if (-not $PSBoundParameters['NoProgressBar']) {
                    Write-Progress -Id 2 -ParentId 1 -Activity "   ($($CurrentAutorunCount+1)/$($AutoRunOptionCount)) Current autoruns type:" -Status $Category -PercentComplete (($CurrentAutorunCount / $AutoRunOptionCount) * 100)
                    $CurrentAutorunCount++
                }

                Get-CSRegistryKey -Hive HKLM -SubKey 'SYSTEM\CurrentControlSet\Control\Print\Monitors' @CommonArgs @Timeout |
                    Get-CSRegistryValue -ValueName Driver @Timeout | ForEach-Object {
                        $_ | New-AutoRunsEntry -SubKey 'SYSTEM\CurrentControlSet\Control\Print\Monitors' -AutoRunEntry $_.SubKey.Split('\')[-1] -Category $Category
                    }
            }

            if (($PSCmdlet.ParameterSetName -ne 'SpecificCheck') -or $PSBoundParameters['NetworkProviders']) {
                $Category = 'NetworkProviders'

                if (-not $PSBoundParameters['NoProgressBar']) {
                    Write-Progress -Id 2 -ParentId 1 -Activity "   ($($CurrentAutorunCount+1)/$($AutoRunOptionCount)) Current autoruns type:" -Status $Category -PercentComplete (($CurrentAutorunCount / $AutoRunOptionCount) * 100)
                    $CurrentAutorunCount++
                }

                $NetworkOrder = Get-CSRegistryValue -Hive HKLM -SubKey 'SYSTEM\CurrentControlSet\Control\NetworkProvider\Order' -ValueName ProviderOrder @CommonArgs @Timeout

                if ($NetworkOrder.ValueContent) {
                    $NetworkOrder.ValueContent.Split(',') | ForEach-Object {
                        $NetworkOrder | New-AutoRunsEntry -AutoRunEntry $_ -ImagePath $_ -Category $Category
                    }
                }
            }

            if (($PSCmdlet.ParameterSetName -ne 'SpecificCheck') -or $PSBoundParameters['LSAProviders']) {
                $Category = 'LSAProviders'

                if (-not $PSBoundParameters['NoProgressBar']) {
                    Write-Progress -Id 2 -ParentId 1 -Activity "   ($($CurrentAutorunCount+1)/$($AutoRunOptionCount)) Current autoruns type:" -Status $Category -PercentComplete (($CurrentAutorunCount / $AutoRunOptionCount) * 100)
                    $CurrentAutorunCount++
                }

                $SecProviders = Get-CSRegistryValue -Hive HKLM -SubKey 'SYSTEM\CurrentControlSet\Control\SecurityProviders' @CommonArgs @Timeout
                $SecProviders | New-AutoRunsEntry -ImagePath "$($SecProviders.ValueContent)" -Category $Category

                $AuthPackages = Get-CSRegistryValue -Hive HKLM -SubKey 'SYSTEM\CurrentControlSet\Control\Lsa' -ValueName 'Authentication Packages' @CommonArgs @Timeout
                $AuthPackages | New-AutoRunsEntry -ImagePath "$($AuthPackages.ValueContent)" -Category $Category

                $NotPackages =  Get-CSRegistryValue -Hive HKLM -SubKey 'SYSTEM\CurrentControlSet\Control\Lsa' -ValueName 'Notification Packages' @CommonArgs @Timeout
                $NotPackages | New-AutoRunsEntry -ImagePath "$($NotPackages.ValueContent)" -Category $Category

                $SecPackages = Get-CSRegistryValue -Hive HKLM -SubKey 'SYSTEM\CurrentControlSet\Control\Lsa\OSConfig' -ValueName 'Security Packages' @CommonArgs @Timeout
                $SecPackages | New-AutoRunsEntry -ImagePath "$($SecPackages.ValueContent)" -Category $Category
            }

            if (($PSCmdlet.ParameterSetName -ne 'SpecificCheck') -or $PSBoundParameters['ImageHijacks']) {
                $Category = 'ImageHijacks'

                if (-not $PSBoundParameters['NoProgressBar']) {
                    Write-Progress -Id 2 -ParentId 1 -Activity "   ($($CurrentAutorunCount+1)/$($AutoRunOptionCount)) Current autoruns type:" -Status $Category -PercentComplete (($CurrentAutorunCount / $AutoRunOptionCount) * 100)
                    $CurrentAutorunCount++
                }

                $CommonKeys = @(
                    'SOFTWARE\Classes\htmlfile\shell\open\command',
                    'SOFTWARE\Classes\htafile\shell\open\command',
                    'SOFTWARE\Classes\batfile\shell\open\command',
                    'SOFTWARE\Classes\comfile\shell\open\command',
                    'SOFTWARE\Classes\piffile\shell\open\command',
                    'SOFTWARE\Classes\exefile\shell\open\command'
                )

                foreach ($CommonKey in $CommonKeys) {
                    Get-CSRegistryValue -Hive HKLM -SubKey $CommonKey -ValueName '' @CommonArgs @Timeout |
                        New-AutoRunsEntry -AutoRunEntry $CommonKey.Split('\')[2] -Category $Category

                    # Iterate over each local user hive
                    foreach ($SID in $HKUSIDs) {
                        Get-CSRegistryValue -Hive HKU -SubKey "$SID\$CommonKey" -ValueName '' @CommonArgs @Timeout |
                            New-AutoRunsEntry -AutoRunEntry $CommonKey.Split('\')[2] -Category $Category
                    }
                }

                Get-CSRegistryValue -Hive HKLM -SubKey SOFTWARE\Classes\exefile\shell\open\command -ValueName 'IsolatedCommand' @CommonArgs @Timeout |
                    New-AutoRunsEntry -Category $Category

                $null, 'Wow6432Node\' | ForEach-Object {
                    Get-CSRegistryKey -Hive HKLM -SubKey "SOFTWARE\$($_)Microsoft\Windows NT\CurrentVersion\Image File Execution Options" @CommonArgs @Timeout |
                        Get-CSRegistryValue -ValueName Debugger @Timeout | ForEach-Object {
                            $_ | New-AutoRunsEntry -AutoRunEntry $_.SubKey.Substring($_.SubKey.LastIndexOf('\') + 1) -Category $Category
                        }

                    Get-CSRegistryValue -Hive HKLM -SubKey "SOFTWARE\$($_)Microsoft\Command Processor" -ValueName 'Autorun' @CommonArgs @Timeout |
                        New-AutoRunsEntry -Category $Category
                }

                $Class_exe = Get-CSRegistryValue -Hive HKLM -SubKey 'SOFTWARE\Classes\.exe' -ValueName '' -ValueType REG_SZ @CommonArgs @Timeout

                if ($Class_exe.ValueContent) {
                    $OpenCommand = Get-CSRegistryValue -Hive HKLM -SubKey "SOFTWARE\Classes\$($Class_exe.ValueContent)\Shell\Open\Command" -ValueName '' -ValueType REG_SZ @CommonArgs @Timeout

                    if ($OpenCommand.ValueContent) {
                        $OpenCommand | New-AutoRunsEntry -Hive $Class_exe.Hive -SubKey $Class_exe.SubKey -AutoRunEntry $Class_exe.ValueContent -Category $Category
                    }
                }

                $Class_cmd = Get-CSRegistryValue -Hive HKLM -SubKey 'SOFTWARE\Classes\.cmd' -ValueName '' -ValueType REG_SZ @CommonArgs @Timeout

                if ($Class_cmd.ValueContent) {
                    $OpenCommand = Get-CSRegistryValue -Hive HKLM -SubKey "SOFTWARE\Classes\$($Class_cmd.ValueContent)\Shell\Open\Command" -ValueName '' -ValueType REG_SZ @CommonArgs @Timeout

                    if ($OpenCommand.ValueContent) {
                        $OpenCommand | New-AutoRunsEntry -Hive $Class_cmd.Hive -SubKey $Class_cmd.SubKey -AutoRunEntry $Class_cmd.ValueContent -Category $Category
                    }
                }

                foreach ($SID in $HKUSIDs) {
                    Get-CSRegistryValue -Hive HKU -SubKey "$SID\SOFTWARE\Microsoft\Command Processor" -ValueName 'Autorun' @CommonArgs @Timeout |
                        New-AutoRunsEntry -Category $Category

                    $Class_exe = Get-CSRegistryValue -Hive HKU -SubKey "$SID\SOFTWARE\Classes\.exe" -ValueName '' -ValueType REG_SZ @CommonArgs @Timeout

                    if ($Class_exe.ValueContent) {
                        $OpenCommand = Get-CSRegistryValue -Hive HKU -SubKey "$SID\SOFTWARE\Classes\$($Class_exe.ValueContent)\Shell\Open\Command" -ValueName '' -ValueType REG_SZ @CommonArgs @Timeout

                        if ($OpenCommand.ValueContent) {
                            $OpenCommand | New-AutoRunsEntry -Hive $Class_exe.Hive -SubKey $Class_exe.SubKey -AutoRunEntry $Class_exe.ValueContent -Category $Category
                        }
                    }

                    $Class_cmd = Get-CSRegistryValue -Hive HKU -SubKey "$SID\SOFTWARE\Classes\.cmd" -ValueName '' -ValueType REG_SZ @CommonArgs @Timeout

                    if ($Class_cmd.ValueContent) {
                        $OpenCommand = Get-CSRegistryValue -Hive HKU -SubKey "$SID\SOFTWARE\Classes\$($Class_cmd.ValueContent)\Shell\Open\Command" -ValueName '' -ValueType REG_SZ @CommonArgs @Timeout

                        if ($OpenCommand.ValueContent) {
                            $OpenCommand | New-AutoRunsEntry -Hive $Class_cmd.Hive -SubKey $Class_cmd.SubKey -AutoRunEntry $Class_cmd.ValueContent -Category $Category
                        }
                    }
                }
            }

            if (($PSCmdlet.ParameterSetName -ne 'SpecificCheck') -or $PSBoundParameters['AppInit']) {
                $Category = 'AppInit'

                if (-not $PSBoundParameters['NoProgressBar']) {
                    Write-Progress -Id 2 -ParentId 1 -Activity "   ($($CurrentAutorunCount+1)/$($AutoRunOptionCount)) Current autoruns type:" -Status $Category -PercentComplete (($CurrentAutorunCount / $AutoRunOptionCount) * 100)
                    $CurrentAutorunCount++
                }

                $null,'Wow6432Node\' | ForEach-Object {
                    Get-CSRegistryValue -Hive HKLM -SubKey "SOFTWARE\$($_)Microsoft\Windows NT\CurrentVersion\Windows" -ValueName 'AppInit_DLLs' @CommonArgs @Timeout |
                        New-AutoRunsEntry -Category $Category
                    Get-CSRegistryValue -Hive HKLM -SubKey "SOFTWARE\$($_)Microsoft\Command Processor" -ValueName 'Autorun' @CommonArgs @Timeout |
                        New-AutoRunsEntry -Category $Category
                }

                Get-CSRegistryValue -Hive HKLM -SubKey 'SYSTEM\CurrentControlSet\Control\Session Manager\AppCertDlls' @CommonArgs @Timeout |
                    New-AutoRunsEntry -Category $Category
            }

            if (($PSCmdlet.ParameterSetName -ne 'SpecificCheck') -or $PSBoundParameters['KnownDLLs']) {
                $Category = 'KnownDLLs'

                if (-not $PSBoundParameters['NoProgressBar']) {
                    Write-Progress -Id 2 -ParentId 1 -Activity "   ($($CurrentAutorunCount+1)/$($AutoRunOptionCount)) Current autoruns type:" -Status $Category -PercentComplete (($CurrentAutorunCount / $AutoRunOptionCount) * 100)
                    $CurrentAutorunCount++
                }

                Get-CSRegistryValue -Hive HKLM -SubKey 'SYSTEM\CurrentControlSet\Control\Session Manager\KnownDLLs' @CommonArgs @Timeout |
                    New-AutoRunsEntry -Category $Category
            }

            if (($PSCmdlet.ParameterSetName -ne 'SpecificCheck') -or $PSBoundParameters['Winlogon']) {
                $Category = 'Winlogon'

                if (-not $PSBoundParameters['NoProgressBar']) {
                    Write-Progress -Id 2 -ParentId 1 -Activity "   ($($CurrentAutorunCount+1)/$($AutoRunOptionCount)) Current autoruns type:" -Status $Category -PercentComplete (($CurrentAutorunCount / $AutoRunOptionCount) * 100)
                    $CurrentAutorunCount++
                }

                $CmdLine = Get-CSRegistryValue -Hive HKLM -SubKey 'SYSTEM\Setup' -ValueName 'CmdLine' @CommonArgs @Timeout

                if ($CmdLine -and $CmdLine.ValueContent) {
                    $CmdLine | New-AutoRunsEntry -Category $Category
                }

                'Credential Providers', 'Credential Provider Filters', 'PLAP Providers' |
                    ForEach-Object { Get-CSRegistryKey -Hive HKLM -SubKey "SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\$_" @CommonArgs @Timeout } | ForEach-Object {
                        $LastBSIndex = $_.SubKey.LastIndexOf('\')
                        $ParentKey = $_.SubKey.Substring(0, $LastBSIndex)
                        $Guid = $_.SubKey.Substring($LastBSIndex + 1)

                        if ($Guid -as [Guid]) {
                            $AutoRunEntry = Get-CSRegistryValue -Hive HKLM -SubKey "SOFTWARE\Classes\CLSID\$Guid" -ValueName '' -ValueType REG_SZ @CommonArgs @Timeout
                            $InprocServer32 = Get-CSRegistryValue -Hive HKLM -SubKey "SOFTWARE\Classes\CLSID\$Guid\InprocServer32" -ValueName '' -ValueType REG_EXPAND_SZ @CommonArgs @Timeout

                            New-AutoRunsEntry $_.Hive $ParentKey $AutoRunEntry.ValueContent $InprocServer32.ValueContent $Category $_.PSComputerName
                        }
                    }

                $BootVer = Get-CSRegistryValue -Hive HKLM -SubKey 'SYSTEM\CurrentControlSet\Control\BootVerificationProgram' -ValueName 'ImagePath' @CommonArgs @Timeout

                if ($BootVer) {
                    $BootVer | New-AutoRunsEntry -Hive $BootVer.Hive -SubKey "$($BootVer.SubKey)\ImagePath"
                }

                foreach ($SID in $HKUSIDs) {
                    $Scrnsave = Get-CSRegistryValue -Hive HKU -SubKey "$SID\SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop" -ValueName 'Scrnsave.exe' @CommonArgs @Timeout
                    if ($Scrnsave) { $Scrnsave | New-AutoRunsEntry -Category $Category }

                    $Scrnsave = Get-CSRegistryValue -Hive HKU -SubKey "$SID\Control Panel\Desktop" -ValueName 'Scrnsave.exe' @CommonArgs @Timeout
                    if ($Scrnsave) { $Scrnsave | New-AutoRunsEntry -Category $Category }
                }
            }
        }
    }
}

function Get-CSStartMenuEntry {
<#
.SYNOPSIS

List user and common start menu items.

Author: Matthew Graeber (@mattifestation)
License: BSD 3-Clause

.DESCRIPTION

Get-CSStartMenuEntry returns file information for all files present (excluding desktop.ini) in user and system-wide start menus.

.PARAMETER NoProgressBar

Do not display a progress bar. This parameter is designed to be used with wrapper functions.

.PARAMETER CimSession

Specifies the CIM session to use for this cmdlet. Enter a variable that contains the CIM session or a command that creates or gets the CIM session, such as the New-CimSession or Get-CimSession cmdlets. For more information, see about_CimSessions.

.PARAMETER OperationTimeoutSec

Specifies the amount of time that the cmdlet waits for a response from the computer.

By default, the value of this parameter is 0, which means that the cmdlet uses the default timeout value for the server.

If the OperationTimeoutSec parameter is set to a value less than the robust connection retry timeout of 3 minutes, network failures that last more than the value of the OperationTimeoutSec parameter are not recoverable, because the operation on the server times out before the client can reconnect.

.EXAMPLE

Get-CSStartMenuEntry

Lists all files present in user and system-level start menus on a local system.

.EXAMPLE

Get-CSStartMenuEntry -CimSession $CimSession

Lists all files present in user and system-level start menus on a remote system.

.OUTPUTS

Microsoft.Management.Infrastructure.CimInstance#root/cimv2/Win32_ShortcutFile

Get-CSStartMenuEntry outputs Win32_ShortcutFile objects representing LNK files present in the start menus.

.NOTES

If a shortcut is present in the start menu, an instance of a Win32_ShortcutFile is returned that has a Target property.
#>

    [OutputType('Microsoft.Management.Infrastructure.CimInstance#root/cimv2/Win32_ShortcutFile')]
    [CmdletBinding()]
    param(
        [Switch]
        $NoProgressBar,

        [Alias('Session')]
        [ValidateNotNullOrEmpty()]
        [Microsoft.Management.Infrastructure.CimSession[]]
        $CimSession,

        [UInt32]
        [Alias('OT')]
        $OperationTimeoutSec
    )

    BEGIN {
        # If a CIM session is not provided, trick the function into thinking there is one.
        if (-not $PSBoundParameters['CimSession']) {
            $CimSession = ''
            $CIMSessionCount = 1
        } else {
            $CIMSessionCount = $CimSession.Count
        }

        $CurrentCIMSession = 0

        $Timeout = @{}
        if ($PSBoundParameters['OperationTimeoutSec']) { $Timeout['OperationTimeoutSec'] = $OperationTimeoutSec }
    }

    PROCESS {
        foreach ($Session in $CimSession) {
            $ComputerName = $Session.ComputerName
            if (-not $Session.ComputerName) { $ComputerName = 'localhost' }

            if (-not $PSBoundParameters['NoProgressBar']) {
                # Display a progress activity for each CIM session
                Write-Progress -Id 1 -Activity 'CimSweep - Temp directory sweep' -Status "($($CurrentCIMSession+1)/$($CIMSessionCount)) Current computer: $ComputerName" -PercentComplete (($CurrentCIMSession / $CIMSessionCount) * 100)
                $CurrentCIMSession++
            }

            $CommonArgs = @{}

            if ($Session.Id) { $CommonArgs['CimSession'] = $Session }

            Get-CSShellFolderPath -SystemFolder -FolderName 'Common Startup' -NoProgressBar @CommonArgs @Timeout | ForEach-Object {
                Get-CSDirectoryListing -DirectoryPath $_.ValueContent -File @CommonArgs @Timeout | Where-Object {
                    $_.FileName -ne 'desktop' -and $_.Extension -ne 'ini'
                }
            }

            Get-CSShellFolderPath -UserFolder -FolderName 'Startup' -NoProgressBar @CommonArgs @Timeout | ForEach-Object {
                Get-CSDirectoryListing -DirectoryPath $_.ValueContent -File @CommonArgs @Timeout | Where-Object {
                    $_.FileName -ne 'desktop' -and $_.Extension -ne 'ini'
                }
            }
        }
    }
}

function Get-CSWmiPersistence {
<#
.SYNOPSIS

List registered permanent WMI event subscriptions.

Author: Matthew Graeber (@mattifestation)
License: BSD 3-Clause

.DESCRIPTION

Get-CSWmiPersistence lists all registered __FilterToConsumerBinding objects and the __EventFilter and __EventConsumer that the binding corresponds to.

.PARAMETER CimSession

Specifies the CIM session to use for this cmdlet. Enter a variable that contains the CIM session or a command that creates or gets the CIM session, such as the New-CimSession or Get-CimSession cmdlets. For more information, see about_CimSessions.

.PARAMETER OperationTimeoutSec

Specifies the amount of time that the cmdlet waits for a response from the computer.

By default, the value of this parameter is 0, which means that the cmdlet uses the default timeout value for the server.

If the OperationTimeoutSec parameter is set to a value less than the robust connection retry timeout of 3 minutes, network failures that last more than the value of the OperationTimeoutSec parameter are not recoverable, because the operation on the server times out before the client can reconnect.

.EXAMPLE

Get-CSWmiPersistence

List all __FilterToConsumerBinding instances with their corresponding __EventFilter and __EventConsumer.

.OUTPUTS

CimSweep.WmiPersistence

Outputs objects representing the combination of __EventFilter, __EventConsumer, and __FilterToConsumerBinding.

.NOTES

Get-CSWmiPersistence only returns output when __FilterToConsumerBinding instances exist which implies installed WMI persistence. You may still want to enumerate __EventConsumer instances which may be remnants of a previous attack (e.g. ActiveScriptEventConsumer and CommandLineEventConsumer).
#>

    [CmdletBinding()]
    [OutputType('CimSweep.WmiPersistence')]
    param(
        [Alias('Session')]
        [ValidateNotNullOrEmpty()]
        [Microsoft.Management.Infrastructure.CimSession[]]
        $CimSession,

        [UInt32]
        [Alias('OT')]
        $OperationTimeoutSec
    )

    BEGIN {
        if (-not $PSBoundParameters['CimSession']) {
            # i.e. Run the function locally
            $CimSession = ''
            # Trick the loop below into thinking there's at least one CimSession
            $SessionCount = 1
        } else {
            $SessionCount = $CimSession.Count
        }

        $Current = 0

        $Timeout = @{}
        if ($PSBoundParameters['OperationTimeoutSec']) { $Timeout['OperationTimeoutSec'] = $OperationTimeoutSec }
    }

    PROCESS {
        foreach ($Session in $CimSession) {
            Write-Progress -Activity 'CimSweep - WMI persistence sweep' -Status "($($Current+1)/$($SessionCount)) Current computer: $($Session.ComputerName)" -PercentComplete (($Current / $SessionCount) * 100)
            $Current++

            $CommonArgs = @{}

            if ($Session.Id) { $CommonArgs['CimSession'] = $Session }

            Write-Verbose "[$($Session.ComputerName)] Retrieving __FilterToConsumerBinding instance."

            Get-CimInstance -Namespace root/subscription -ClassName __FilterToConsumerBinding @CommonArgs @Timeout | ForEach-Object {
                Write-Verbose "[$($Session.ComputerName)] Correlating referenced __EventFilter instance."
                $Filter = Get-CimInstance -Namespace root/subscription -ClassName __EventFilter -Filter "Name=`"$($_.Filter.Name)`"" @CommonArgs @Timeout

                $ConsumerClass = $_.Consumer.PSObject.TypeNames[0].Split('/')[-1]
                Write-Verbose "[$($Session.ComputerName)] Correlating referenced __EventConsumer instance."
                $Consumer = Get-CimInstance -Namespace root/subscription -ClassName $ConsumerClass -Filter "Name=`"$($_.Consumer.Name)`"" @CommonArgs @Timeout

                [PSCustomObject] @{
                    PSTypeName = 'CimSweep.WmiPersistence'
                    Filter = $Filter
                    ConsumerClass = $ConsumerClass
                    Consumer = $Consumer
                    FilterToConsumerBinding = $_
                    PSComputerName = $_.PSComputerName
                }
            }
        }
    }
}

function Get-CSComHijackPersistence{
<#
.SYNOPSIS

List artifacts of COM hijacking.

Author: Josh Day (@josh__day)
License: TBD

.DESCRIPTION

Get-CSComHijackPersistence lists all evidence of COM hijacks to include User hive hijacks and "TreatAs" hijacking.

.PARAMETER CimSession

Specifies the CIM session to use for this cmdlet. Enter a variable that contains the CIM session or a command that creates or gets the CIM session, such as the New-CimSession or Get-CimSession cmdlets. For more information, see about_CimSessions.

.PARAMETER OperationTimeoutSec

Specifies the amount of time that the cmdlet waits for a response from the computer.

By default, the value of this parameter is 0, which means that the cmdlet uses the default timeout value for the server.

If the OperationTimeoutSec parameter is set to a value less than the robust connection retry timeout of 3 minutes, network failures that last more than the value of the OperationTimeoutSec parameter are not recoverable, because the operation on the server times out before the client can reconnect.

.EXAMPLE

Get-CSComHijackPersistence

List all artifacts of COM hijacking

.OUTPUTS

CimSweep.ComHijack

Outputs object showing path in registry to COM hijack evidence and specified binary and options (if any)

.NOTES

Get-CSComHijackPersistence only returns output when there is a mismatch between a user hive and local machine hive, or when a TreatAs key has been set, redirecting to an alternate COM registry key.
#>

    [CmdletBinding()]
    [OutputType('CimSweep.ComHijack')]
    param(
        [Alias('Session')]
        [ValidateNotNullOrEmpty()]
        [Microsoft.Management.Infrastructure.CimSession[]]
        $CimSession,

        [UInt32]
        [Alias('OT')]
        $OperationTimeoutSec
    )

    BEGIN {
        if (-not $PSBoundParameters['CimSession']) {
            # i.e. Run the function locally
            $CimSession = ''
            # Trick the loop below into thinking there's at least one CimSession
            $SessionCount = 1
        } else {
            $SessionCount = $CimSession.Count
        }

        filter New-ComHijack {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
            Param (
                [Parameter(Position = 0)]
                [String]
                $Hive,

                [Parameter(Position = 1)]
                [String]
                $SubKey,

                [Parameter(Position = 2)]
                [String]
                $PreviousPath,

                [Parameter(Position = 3, Mandatory = $true)]
                [String]
                $ImagePath,

                [Parameter(Position = 4)]
                [String]
                $Arguments = $null,

                [Parameter(Position = 5, ValueFromPipelineByPropertyName = $True)]
                [String]
                $PSComputerName,

                [Parameter(ValueFromPipelineByPropertyName = $True)]
                [Alias('Session')]
                [Microsoft.Management.Infrastructure.CimSession]
                $CimSession
            )

            $ObjectProperties = [Ordered] @{
                PSTypeName = 'CimSweep.ComHijack'
                Path = "$($Hive)\$($SubKey)"
                PreviousImage = $PreviousPath
                HijackImagePath = $ImagePath
                Arguments = $Arguments
            }

            $DefaultProperties = 'Path', 'PreviousImage', 'HijackImagePath', 'Arguments' -as [Type] 'Collections.Generic.List[String]'

            if ($PSComputerName) {
                $ObjectProperties['PSComputerName'] = $PSComputerName
                $DefaultProperties.Add('PSComputerName')
            } else {
                $ObjectProperties['PSComputerName'] = $null
            }

            if ($Session.Id) { $ObjectProperties['CimSession'] = $Session }

            $ComHijack = [PSCustomObject] $ObjectProperties

            Set-DefaultDisplayProperty -InputObject $ComHijack -PropertyNames $DefaultProperties

            $ComHijack
        }

        $Current = 0

        $Timeout = @{}
        if ($PSBoundParameters['OperationTimeoutSec']) { $Timeout['OperationTimeoutSec'] = $OperationTimeoutSec }
    }

    PROCESS {
        foreach ($Session in $CimSession) {

            #DEBUG timing
            $timer = [Diagnostics.Stopwatch]::StartNew()

            $ComputerName = $Session.ComputerName
            if (-not $Session.ComputerName) { $ComputerName = 'localhost' }
            Write-Progress -Activity 'CimSweep - COM Hijack persistence sweep' -Status "($($Current+1)/$($SessionCount)) Current computer: $ComputerName" -PercentComplete (($Current / $SessionCount) * 100)
            $Current++

            $CommonArgs = @{}

            if ($Session.Id) { $CommonArgs['CimSession'] = $Session }

            Write-Verbose "[$($Session.ComputerName)] Retrieving instances of COM hijacking...this may take a while."

            $hklm_clsid = @{}


            #TODO: revamp this function and wow64 hklm function to increase speed. Current avg time takes about 3 minutes per.
            Get-CSRegistryKey -Hive HKLM -SubKey 'SOFTWARE\Classes\CLSID' @CommonArgs @Timeout | ForEach-Object {
                $path = $_.subkey
                $clsid = $path.split("\")[-1]
                if ($clsid -ne "CLSID"){
                    #Process CLSID subkeys
                    $com_obj = New-Object PSObject
                    $com_obj | Add-Member -type NoteProperty -name CLSID -value $clsid
                    $com_obj | Add-Member -type NoteProperty -name subkey -value $path

                    $desc = (Get-CSRegistryValue -Hive HKLM -SubKey $path -ValueType "REG_SZ" @CommonArgs @Timeout | Where-Object { $_.ValueName -eq "(Default)" }).ValueContent
                    if ($desc -ne $null){
                        $com_obj | Add-Member -type NoteProperty -name description -value $desc
                    }

                    Get-CSRegistryKey -Hive HKLM -SubKey $path @CommonArgs @Timeout | ForEach-Object {
                        $short_name = $_.subkey.split('\')[-1]

                        if ($short_name -match '(inproc(handler|server)|localserver)(32)?'){
                            $prop_value = (Get-CSRegistryValue -Hive HKLM -SubKey $_.subkey -ValueType "REG_SZ" @CommonArgs @Timeout | Where-Object {
                                $_.ValueName -eq "(Default)"
                            }).ValueContent
                            if ($prop_value -ne $null){
                                $com_obj | Add-Member -type NoteProperty -name $matches[1] -value $prop_value
                            }
                        }

                        elseif ($short_name -match 'scriptleturl'){
                            $prop_value = (Get-CSRegistryValue -Hive HKLM -SubKey $_.subkey -ValueType "REG_SZ" @CommonArgs @Timeout | Where-Object {
                                $_.ValueName -eq "(Default)"
                            }).ValueContent
                            if ($prop_value -ne $null){
                                $com_obj | Add-Member -type NoteProperty -name "ScriptletURL" -value $prop_value
                            }
                        }

                        elseif ($short_name -match '^treatas'){
                            $prop_value = (Get-CSRegistryValue -Hive HKLM -SubKey $_.subkey -ValueType "REG_SZ" @CommonArgs @Timeout | Where-Object {
                                $_.ValueName -eq "(Default)"
                            }).ValueContent
                            if ($prop_value -ne $null){
                                $com_obj | Add-Member -type NoteProperty -name "TreatAs" -value $prop_value
                            }
                        }
                    }

                    $hklm_clsid.add($clsid, $com_obj)
                }
            }

            #DEBUG timing
            #write-host "finished hklm parsing [$($timer.elapsed.minutes).$($timer.elapsed.seconds).$($timer.elapsed.milliseconds) seconds]"

            #TreatAs HKLM -> HKLM hijacking
            foreach ($item in $hklm_clsid.keys){
                if (($hklm_clsid[$item].TreatAs -ne $null) -and (($hklm_clsid[$item].InProcServer -ne $null) -or ($hklm_clsid[$item].LocalServer -ne $null) -or ($hklm_clsid[$item].InProcHandler -ne $null))){
                    if (($hklm_clsid[$hklm_clsid[$item].TreatAs].InProcServer -ne $null) -and ($hklm_clsid[$hklm_clsid[$item].TreatAs].InProcServer -ne $hklm_clsid[$item].InProcServer)){
                        if ($hklm_clsid[$hklm_clsid[$item].TreatAs].ScriptletURL -ne $null){
                            New-ComHijack -Hive HKLM -SubKey $hklm_clsid[$item].subkey -PreviousPath $hklm_clsid[$item].InProcServer -ImagePath $hklm_clsid[$hklm_clsid[$item].TreatAs].InProcServer -Arguments $hklm_clsid[$hklm_clsid[$item].TreatAs].ScriptletURL -PSComputerName $computerName
                        }
                        else{
                            New-ComHijack -Hive HKLM -SubKey $hklm_clsid[$item].subkey -PreviousPath $hklm_clsid[$item].InProcServer -ImagePath $hklm_clsid[$hklm_clsid[$item].TreatAs].InProcServer -PSComputerName $computerName
                        }
                    }
                    elseif (($hklm_clsid[$hklm_clsid[$item].TreatAs].LocalServer -ne $null) -and ($hklm_clsid[$hklm_clsid[$item].TreatAs].LocalServer -ne $hklm_clsid[$item].LocalServer)){
                        New-ComHijack -Hive HKLM -SubKey $hklm_clsid[$item].subkey -PreviousPath $hklm_clsid[$item].LocalServer -ImagePath $hklm_clsid[$hklm_clsid[$item].TreatAs].LocalServer -PSComputerName $computerName
                    }
                    elseif (($hklm_clsid[$hklm_clsid[$item].TreatAs].InProcHandler -ne $null) -and ($hklm_clsid[$hklm_clsid[$item].TreatAs].InProcHandler -ne $hklm_clsid[$item].InProcHandler)){
                        if ($hklm_clsid[$hklm_clsid[$item].TreatAs].ScriptletURL -ne $null){
                            New-ComHijack -Hive HKLM -SubKey $hklm_clsid[$item].subkey -PreviousPath $hklm_clsid[$item].InProcHandler -ImagePath $hklm_clsid[$hklm_clsid[$item].TreatAs].InProcHandler -Arguments $hklm_clsid[$hklm_clsid[$item].TreatAs].ScriptletURL -PSComputerName $computerName
                        }
                        else{
                            New-ComHijack -Hive HKLM -SubKey $hklm_clsid[$item].subkey -PreviousPath $hklm_clsid[$item].LocalServer -ImagePath $hklm_clsid[$hklm_clsid[$item].TreatAs].InProcHandler -PSComputerName $computerName
                        }
                    }
                }
            }

            #DEBUG timing
            #write-host "finished hklm treatAs hijack check [$($timer.elapsed.minutes).$($timer.elapsed.seconds).$($timer.elapsed.milliseconds) seconds]"

            $hklm_wow64_clsid = @{}

            Get-CSRegistryKey -Hive HKLM -SubKey 'SOFTWARE\Classes\WOW6432Node\CLSID' @CommonArgs @Timeout | ForEach-Object {
                $path = $_.subkey
                $clsid = $path.split("\")[-1]
                if ($clsid -ne "CLSID"){
                    #Process CLSID subkeys
                    $com_obj = New-Object PSObject
                    $com_obj | Add-Member -type NoteProperty -name CLSID -value $clsid
                    $com_obj | Add-Member -type NoteProperty -name subkey -value $path

                    $desc = (Get-CSRegistryValue -Hive HKLM -SubKey $path -ValueType "REG_SZ" @CommonArgs @Timeout | Where-Object { $_.ValueName -eq "(Default)" }).ValueContent
                    if ($desc -ne $null){
                        $com_obj | Add-Member -type NoteProperty -name description -value $desc
                    }

                    Get-CSRegistryKey -Hive HKLM -SubKey $path @CommonArgs @Timeout | ForEach-Object {
                        $short_name = $_.subkey.split('\')[-1]

                        if ($short_name -match '(inproc(handler|server)|localserver)(32)?'){
                            $prop_value = (Get-CSRegistryValue -Hive HKLM -SubKey $_.subkey -ValueType "REG_SZ" @CommonArgs @Timeout | Where-Object {
                                $_.ValueName -eq "(Default)"
                            }).ValueContent
                            if ($prop_value -ne $null){
                                $com_obj | Add-Member -type NoteProperty -name $matches[1] -value $prop_value
                            }
                        }

                        elseif ($short_name -match 'scriptleturl'){
                            $prop_value = (Get-CSRegistryValue -Hive HKLM -SubKey $_.subkey -ValueType "REG_SZ" @CommonArgs @Timeout | Where-Object {
                                $_.ValueName -eq "(Default)"
                            }).ValueContent
                            if ($prop_value -ne $null){
                                $com_obj | Add-Member -type NoteProperty -name "ScriptletURL" -value $prop_value
                            }
                        }

                        elseif ($short_name -match '^treatas'){
                            $prop_value = (Get-CSRegistryValue -Hive HKLM -SubKey $_.subkey -ValueType "REG_SZ" @CommonArgs @Timeout | Where-Object {
                                $_.ValueName -eq "(Default)"
                            }).ValueContent
                            if ($prop_value -ne $null){
                                $com_obj | Add-Member -type NoteProperty -name "TreatAs" -value $prop_value
                            }
                        }
                    }

                    $hklm_wow64_clsid.add($clsid, $com_obj)
                }
            }

            #DEBUG timing
            #write-host "finished hklm wow64 parsing [$($timer.elapsed.minutes).$($timer.elapsed.seconds).$($timer.elapsed.milliseconds) seconds]"

            # TreatAs HKLM -> HKLM hijacking (WOW6432Node)
            foreach ($item in $hklm_wow64_clsid.keys){
                if (($hklm_wow64_clsid[$item].TreatAs -ne $null) -and (($hklm_wow64_clsid[$item].InProcServer -ne $null) -or ($hklm_wow64_clsid[$item].LocalServer -ne $null) -or ($hklm_wow64_clsid[$item].InProcHandler -ne $null))){
                    if (($hklm_wow64_clsid[$hklm_wow64_clsid[$item].TreatAs].InProcServer -ne $null) -and ($hklm_wow64_clsid[$hklm_wow64_clsid[$item].TreatAs].InProcServer -ne $hklm_wow64_clsid[$item].InProcServer)){
                        if ($hklm_wow64_clsid[$hklm_wow64_clsid[$item].TreatAs].ScriptletURL -ne $null){
                            New-ComHijack -Hive HKLM -SubKey $hklm_wow64_clsid[$item].subkey -PreviousPath $hklm_wow64_clsid[$item].InProcServer -ImagePath $hklm_wow64_clsid[$hklm_wow64_clsid[$item].TreatAs].InProcServer -Arguments $hklm_wow64_clsid[$hklm_wow64_clsid[$item].TreatAs].ScriptletURL -PSComputerName $computerName
                        }
                        else{
                            New-ComHijack -Hive HKLM -SubKey $hklm_wow64_clsid[$item].subkey -PreviousPath $hklm_wow64_clsid[$item].InProcServer -ImagePath $hklm_wow64_clsid[$hklm_wow64_clsid[$item].TreatAs].InProcServer -PSComputerName $computerName
                        }
                    }
                    elseif (($hklm_wow64_clsid[$hklm_wow64_clsid[$item].TreatAs].LocalServer -ne $null) -and ($hklm_wow64_clsid[$hklm_wow64_clsid[$item].TreatAs].LocalServer -ne $hklm_wow64_clsid[$item].LocalServer)){
                        New-ComHijack -Hive HKLM -SubKey $hklm_wow64_clsid[$item].subkey -PreviousPath $hklm_wow64_clsid[$item].InProcServer -ImagePath $hklm_wow64_clsid[$hklm_wow64_clsid[$item].TreatAs].LocalServer -PSComputerName $computerName
                    }
                    elseif (($hklm_wow64_clsid[$hklm_wow64_clsid[$item].TreatAs].InProcHandler -ne $null) -and ($hklm_wow64_clsid[$hklm_wow64_clsid[$item].TreatAs].InProcHandler -ne $hklm_wow64_clsid[$item].InProcHandler)){
                        if ($hklm_wow64_clsid[$hklm_wow64_clsid[$item].TreatAs].ScriptletURL -ne $null){
                            New-ComHijack -Hive HKLM -SubKey $hklm_wow64_clsid[$item].subkey -PreviousPath $hklm_wow64_clsid[$item].InProcHandler -ImagePath $hklm_wow64_clsid[$hklm_wow64_clsid[$item].TreatAs].InProcHandler -Arguments $hklm_wow64_clsid[$hklm_wow64_clsid[$item].TreatAs].ScriptletURL -PSComputerName $computerName
                        }
                        else{
                            New-ComHijack -Hive HKLM -SubKey $hklm_wow64_clsid[$item].subkey -PreviousPath $hklm_wow64_clsid[$item].InProcServer -ImagePath $hklm_wow64_clsid[$hklm_wow64_clsid[$item].TreatAs].InProcHandler -PSComputerName $computerName
                        }
                    }
                }
            }

            #DEBUG timing
            #write-host "finished hklm wow64 treatAs hijack check [$($timer.elapsed.minutes).$($timer.elapsed.seconds).$($timer.elapsed.milliseconds) seconds]"

            # fix TreatAs redirection
            foreach ($item in $hklm_clsid.keys){
                $hklm_clsid[$item] | where-object {
                    $_.treatas -ne $null
                } | foreach-object {
                    if ($hklm_clsid[$_.TreatAs].InProcServer -ne $null){
                        $hklm_clsid[$_.CLSID] | Add-Member -type noteproperty -name "InProcServer" -value $hklm_clsid[$_.TreatAs].InProcServer -force
                    }
                    if ($hklm_clsid[$_.TreatAs].InProcHandler -ne $null){
                        $hklm_clsid[$_.CLSID] | Add-Member -type noteproperty -name "InProcHandler" -value $hklm_clsid[$_.TreatAs].InProcHandler -force
                    }
                    if ($hklm_clsid[$_.TreatAs].LocalServer -ne $null){
                        $hklm_clsid[$_.CLSID] | Add-Member -type noteproperty -name "LocalServer" -value $hklm_clsid[$_.TreatAs].LocalServer -force
                    }
                    if ($hklm_clsid[$_.TreatAs].ScriptletURL -ne $null){
                        $hklm_clsid[$_.CLSID] | Add-Member -type noteproperty -name "ScriptletURL" -value $hklm_clsid[$_.TreatAs].ScriptletURL -force
                    }
                    $temp_treatas = $_.TreatAs
                    $_.PSObject.Properties.Remove('TreatAs')
                    if ($hklm_clsid[$temp_treatas].TreatAs -ne $null){
                        $hklm_clsid[$_.CLSID] | Add-Member -type noteproperty -name "TreatAs" -value $hklm_clsid[$temp_treatas].TreatAs -force
                    }
                }
            }

            # fix TreatAs redirection (WOW6432Node)
            foreach ($item in $hklm_wow64_clsid.keys){
                $hklm_wow64_clsid[$item] | where-object {
                    $_.treatas -ne $null
                } | foreach-object {
                    if ($hklm_wow64_clsid[$_.TreatAs].InProcServer -ne $null){
                        $hklm_wow64_clsid[$_.CLSID] | Add-Member -type noteproperty -name "InProcServer" -value $hklm_wow64_clsid[$_.TreatAs].InProcServer -force
                    }
                    if ($hklm_wow64_clsid[$_.TreatAs].InProcHandler -ne $null){
                        $hklm_wow64_clsid[$_.CLSID] | Add-Member -type noteproperty -name "InProcHandler" -value $hklm_wow64_clsid[$_.TreatAs].InProcHandler -force
                    }
                    if ($hklm_wow64_clsid[$_.TreatAs].LocalServer -ne $null){
                        $hklm_wow64_clsid[$_.CLSID] | Add-Member -type noteproperty -name "LocalServer" -value $hklm_wow64_clsid[$_.TreatAs].LocalServer -force
                    }
                    if ($hklm_wow64_clsid[$_.TreatAs].ScriptletURL -ne $null){
                        $hklm_wow64_clsid[$_.CLSID] | Add-Member -type noteproperty -name "ScriptletURL" -value $hklm_wow64_clsid[$_.TreatAs].ScriptletURL -force
                    }
                    $temp_treatas = $_.TreatAs
                    $_.PSObject.Properties.Remove('TreatAs')
                    if ($hklm_wow64_clsid[$temp_treatas].TreatAs -ne $null){
                        $hklm_wow64_clsid[$_.CLSID] | Add-Member -type noteproperty -name "TreatAs" -value $hklm_wow64_clsid[$temp_treatas].TreatAs -force
                    }
                }
            }

            #DEBUG timing
            #write-host "finished hklm treatAs redirection fix [$($timer.elapsed.minutes).$($timer.elapsed.seconds).$($timer.elapsed.milliseconds) seconds]"

            # Get the SIDS for each user in the registry
            $HKUSIDs = Get-HKUSID @CommonArgs @Timeout

            foreach ($sid in $HKUSIDs){
                $hku_clsid = @{}

                #TODO: revamp this function and wow64 hku function to increase speed. Current avg time takes about 35 seconds per.
                Get-CSRegistryKey -Hive HKU -SubKey "$sid\SOFTWARE\Classes\CLSID" @CommonArgs @Timeout | ForEach-Object {
                    $path = $_.subkey
                    $clsid = $path.split("\")[-1]
                    if ($clsid -ne "CLSID"){
                        #Process CLSID subkeys
                        $com_obj = New-Object PSObject
                        $com_obj | Add-Member -type NoteProperty -name CLSID -value $clsid
                        $com_obj | Add-Member -type NoteProperty -name subkey -value $path

                        $desc = (Get-CSRegistryValue -Hive HKU -SubKey $path -ValueType "REG_SZ" @CommonArgs @Timeout | Where-Object { $_.ValueName -eq "(Default)" }).ValueContent
                        if ($desc -ne $null){
                            $com_obj | Add-Member -type NoteProperty -name description -value $desc
                        }

                        Get-CSRegistryKey -Hive HKU -SubKey $path @CommonArgs @Timeout | ForEach-Object {
                            $short_name = $_.subkey.split('\')[-1]

                            if ($short_name -match '(inproc(handler|server)|localserver)(32)?'){
                                $prop_value = (Get-CSRegistryValue -Hive HKU -SubKey $_.subkey -ValueType "REG_SZ" @CommonArgs @Timeout | Where-Object {
                                    $_.ValueName -eq "(Default)"
                                }).ValueContent
                                if ($prop_value -ne $null){
                                    $com_obj | Add-Member -type NoteProperty -name $matches[1] -value $prop_value
                                }
                            }

                            elseif ($short_name -match 'scriptleturl'){
                                $prop_value = (Get-CSRegistryValue -Hive HKU -SubKey $_.subkey -ValueType "REG_SZ" @CommonArgs @Timeout | Where-Object {
                                    $_.ValueName -eq "(Default)"
                                }).ValueContent
                                if ($prop_value -ne $null){
                                    $com_obj | Add-Member -type NoteProperty -name "ScriptletURL" -value $prop_value
                                }
                            }

                            elseif ($short_name -match '^treatas'){
                                $prop_value = (Get-CSRegistryValue -Hive HKU -SubKey $_.subkey -ValueType "REG_SZ" @CommonArgs @Timeout | Where-Object {
                                    $_.ValueName -eq "(Default)"
                                }).ValueContent
                                if ($prop_value -ne $null){
                                    $com_obj | Add-Member -type NoteProperty -name "TreatAs" -value $prop_value
                                }
                            }
                        }

                        $hku_clsid.add($clsid, $com_obj)
                    }
                }

                #DEBUG timing
                #write-host "finished hku parsing for $sid user [$($timer.elapsed.minutes).$($timer.elapsed.seconds).$($timer.elapsed.milliseconds) seconds]"

                # fix up TreatAs redirection
                foreach ($item in $hku_clsid.keys){
                    $hku_clsid[$item] | where-object {
                        $_.treatas -ne $null
                    } | foreach-object {
                        if ($hku_clsid[$_.TreatAs].InProcServer -ne $null){
                            $hku_clsid[$_.CLSID] | Add-Member -type noteproperty -name "InProcServer" -value $hku_clsid[$_.TreatAs].InProcServer -force
                        }
                        if ($hku_clsid[$_.TreatAs].InProcHandler -ne $null){
                            $hku_clsid[$_.CLSID] | Add-Member -type noteproperty -name "InProcHandler" -value $hku_clsid[$_.TreatAs].InProcHandler -force
                        }
                        if ($hku_clsid[$_.TreatAs].LocalServer -ne $null){
                            $hku_clsid[$_.CLSID] | Add-Member -type noteproperty -name "LocalServer" -value $hku_clsid[$_.TreatAs].LocalServer -force
                        }
                        if ($hku_clsid[$_.TreatAs].ScriptletURL -ne $null){
                            $hku_clsid[$_.CLSID] | Add-Member -type noteproperty -name "ScriptletURL" -value $hku_clsid[$_.TreatAs].ScriptletURL -force
                        }
                        $temp_treatas = $_.TreatAs
                        $_.PSObject.Properties.Remove('TreatAs')
                        if ($hku_clsid[$temp_treatas].TreatAs -ne $null){
                            $hku_clsid[$_.CLSID] | Add-Member -type noteproperty -name "TreatAs" -value $hku_clsid[$temp_treatas].TreatAs -force
                        }
                    }
                }

                #DEBUG timing
                #write-host "finished hku treatAs redirection for $sid [$($timer.elapsed.minutes).$($timer.elapsed.seconds).$($timer.elapsed.milliseconds) seconds]"

                #TODO: repeat above steps as long as necessary (do..while ($still_treatAs -ne $null))
                #$still_treatAs = foreach ($item in $hklm_clsid.keys){$hklm_clsid[$item] | where-object {$_.treatas -ne $null} }

                # do comparison here against hklm
                foreach ($item in $hku_clsid.Keys){
                    if ($hklm_clsid.containskey($item)){
                        if (($hklm_clsid[$item].InProcServer -ne $null) -and ($hku_clsid[$item].InProcServer -ne $null)){
                            if ($hklm_clsid[$item].InProcServer.tolower() -ne $hku_clsid[$item].InProcServer.tolower()){
                                if ($hku_clsid[$item].ScriptletURL -ne $null){
                                    New-ComHijack -Hive HKU -SubKey $hku_clsid[$item].subkey -PreviousPath $hklm_clsid[$item].InProcServer -ImagePath $hku_clsid[$item].InProcServer -Arguments $hku_clsid[$item].ScriptletURL -PSComputerName $computerName
                                }
                                else{
                                    New-ComHijack -Hive HKU -SubKey $hku_clsid[$item].subkey -PreviousPath $hklm_clsid[$item].InProcServer -ImagePath $hku_clsid[$item].InProcServer -PSComputerName $computerName
                                }
                            }
                        }
                        if (($hklm_clsid[$item].LocalServer -ne $null) -and ($hku_clsid[$item].LocalServer -ne $null)){
                            if ($hklm_clsid[$item].LocalServer.tolower() -ne $hku_clsid[$item].LocalServer.tolower()){
                                New-ComHijack -Hive HKU -SubKey $hku_clsid[$item].subkey -PreviousPath $hklm_clsid[$item].LocalServer -ImagePath $hku_clsid[$item].LocalServer -PSComputerName $computerName
                            }
                        }
                        if (($hklm_clsid[$item].InProcHandler -ne $null) -and ($hku_clsid[$item].InProcHandler -ne $null)){
                            if ($hklm_clsid[$item].InProcHandler.tolower() -ne $hku_clsid[$item].InProcHandler.tolower()){
                                if ($hku_clsid[$item].ScriptletURL -ne $null){
                                    New-ComHijack -Hive HKU -SubKey $hku_clsid[$item].subkey -PreviousPath $hklm_clsid[$item].InProcHandler -ImagePath $hku_clsid[$item].InProcHandler -Arguments $hku_clsid[$item].ScriptletURL -PSComputerName $computerName
                                }
                                else{
                                    New-ComHijack -Hive HKU -SubKey $hku_clsid[$item].subkey -PreviousPath $hklm_clsid[$item].InProcHandler -ImagePath $hku_clsid[$item].InProcHandler -PSComputerName $computerName
                                }
                            }
                        }
                    }
                }

                #DEBUG timing
                #write-host "finished hku hijack check for $sid [$($timer.elapsed.minutes).$($timer.elapsed.seconds).$($timer.elapsed.milliseconds) seconds]"
            }

            # do wow64 lookups and comparison
            foreach ($sid in $HKUSIDs){
                $hku_wow64_clsid = @{}

                Get-CSRegistryKey -Hive HKU -SubKey "$sid\SOFTWARE\Classes\WOW6432Node\CLSID" @CommonArgs @Timeout | ForEach-Object {
                    $path = $_.subkey
                    $clsid = $path.split("\")[-1]
                    if ($clsid -ne "CLSID"){
                        #Process CLSID subkeys
                        $com_obj = New-Object PSObject
                        $com_obj | Add-Member -type NoteProperty -name CLSID -value $clsid
                        $com_obj | Add-Member -type NoteProperty -name subkey -value $path

                        $desc = (Get-CSRegistryValue -Hive HKU -SubKey $path -ValueType "REG_SZ" @CommonArgs @Timeout | Where-Object { $_.ValueName -eq "(Default)" }).ValueContent
                        if ($desc -ne $null){
                            $com_obj | Add-Member -type NoteProperty -name description -value $desc
                        }

                        Get-CSRegistryKey -Hive HKU -SubKey $path @CommonArgs @Timeout | ForEach-Object {
                            $short_name = $_.subkey.split('\')[-1]

                            if ($short_name -match '(inproc(handler|server)|localserver)(32)?'){
                                $prop_value = (Get-CSRegistryValue -Hive HKU -SubKey $_.subkey -ValueType "REG_SZ" @CommonArgs @Timeout | Where-Object {
                                    $_.ValueName -eq "(Default)"
                                }).ValueContent
                                if ($prop_value -ne $null){
                                    $com_obj | Add-Member -type NoteProperty -name $matches[1] -value $prop_value
                                }
                            }

                            elseif ($short_name -match 'scriptleturl'){
                                $prop_value = (Get-CSRegistryValue -Hive HKU -SubKey $_.subkey -ValueType "REG_SZ" @CommonArgs @Timeout | Where-Object {
                                    $_.ValueName -eq "(Default)"
                                }).ValueContent
                                if ($prop_value -ne $null){
                                    $com_obj | Add-Member -type NoteProperty -name "ScriptletURL" -value $prop_value
                                }
                            }

                            elseif ($short_name -match '^treatas'){
                                $prop_value = (Get-CSRegistryValue -Hive HKU -SubKey $_.subkey -ValueType "REG_SZ" @CommonArgs @Timeout | Where-Object {
                                    $_.ValueName -eq "(Default)"
                                }).ValueContent
                                if ($prop_value -ne $null){
                                    $com_obj | Add-Member -type NoteProperty -name "TreatAs" -value $prop_value
                                }
                            }
                        }

                        $hku_wow64_clsid.add($clsid, $com_obj)
                    }
                }

                #DEBUG timing
                #write-host "finished hku wow64 parsing for $sid user [$($timer.elapsed.minutes).$($timer.elapsed.seconds).$($timer.elapsed.milliseconds) seconds]"

                # fix up TreatAs redirection
                foreach ($item in $hku_wow64_clsid.keys){
                    $hku_wow64_clsid[$item] | where-object {
                        $_.treatas -ne $null
                    } | foreach-object {
                        if ($hku_wow64_clsid[$_.TreatAs].InProcServer -ne $null){
                            $hku_wow64_clsid[$_.CLSID] | Add-Member -type noteproperty -name "InProcServer" -value $hku_wow64_clsid[$_.TreatAs].InProcServer -force
                        }
                        if ($hku_wow64_clsid[$_.TreatAs].InProcHandler -ne $null){
                            $hku_wow64_clsid[$_.CLSID] | Add-Member -type noteproperty -name "InProcHandler" -value $hku_wow64_clsid[$_.TreatAs].InProcHandler -force
                        }
                        if ($hku_wow64_clsid[$_.TreatAs].LocalServer -ne $null){
                            $hku_wow64_clsid[$_.CLSID] | Add-Member -type noteproperty -name "LocalServer" -value $hku_wow64_clsid[$_.TreatAs].LocalServer -force
                        }
                        if ($hku_wow64_clsid[$_.TreatAs].ScriptletURL -ne $null){
                            $hku_wow64_clsid[$_.CLSID] | Add-Member -type noteproperty -name "ScriptletURL" -value $hku_wow64_clsid[$_.TreatAs].ScriptletURL -force
                        }
                        $temp_treatas = $_.TreatAs
                        $_.PSObject.Properties.Remove('TreatAs')
                        if ($hku_wow64_clsid[$temp_treatas].TreatAs -ne $null){
                            $hku_wow64_clsid[$_.CLSID] | Add-Member -type noteproperty -name "TreatAs" -value $hku_wow64_clsid[$temp_treatas].TreatAs -force
                        }
                    }
                }

                #DEBUG timing
                #write-host "finished hku wow64 treatAs redirection for $sid [$($timer.elapsed.minutes).$($timer.elapsed.seconds).$($timer.elapsed.milliseconds) seconds]"

                #TODO: repeat above steps as long as necessary (do..while ($still_treatAs -ne $null))
                #$still_treatAs = foreach ($item in $hklm_wow64_clsid.keys){$hklm_wow64_clsid[$item] | where-object {$_.treatas -ne $null} }

                # do comparison here against hklm
                foreach ($item in $hku_wow64_clsid.Keys){
                    if ($hklm_wow64_clsid.containskey($item)){
                        if (($hklm_wow64_clsid[$item].InProcServer -ne $null) -and ($hku_wow64_clsid[$item].InProcServer -ne $null)){
                            if ($hklm_wow64_clsid[$item].InProcServer.tolower() -ne $hku_wow64_clsid[$item].InProcServer.tolower()){
                                if ($hku_wow64_clsid[$item].ScriptletURL -ne $null){
                                    New-ComHijack -Hive HKU -SubKey $hku_wow64_clsid[$item].subkey -PreviousPath $hklm_wow64_clsid[$item].InProcServer -ImagePath $hku_wow64_clsid[$item].InProcServer -Arguments $hku_wow64_clsid[$item].ScriptletURL -PSComputerName $computerName
                                }
                                else{
                                    New-ComHijack -Hive HKU -SubKey $hku_wow64_clsid[$item].subkey -PreviousPath $hklm_wow64_clsid[$item].InProcServer -ImagePath $hku_wow64_clsid[$item].InProcServer -PSComputerName $computerName
                                }
                            }
                        }
                        if (($hklm_wow64_clsid[$item].LocalServer -ne $null) -and ($hku_wow64_clsid[$item].LocalServer -ne $null)){
                            if ($hklm_wow64_clsid[$item].LocalServer.tolower() -ne $hku_wow64_clsid[$item].LocalServer.tolower()){
                                New-ComHijack -Hive HKU -SubKey $hku_wow64_clsid[$item].subkey -PreviousPath $hklm_wow64_clsid[$item].LocalServer -ImagePath $hku_wow64_clsid[$item].LocalServer -PSComputerName $computerName
                            }
                        }
                        if (($hklm_wow64_clsid[$item].InProcHandler -ne $null) -and ($hku_wow64_clsid[$item].InProcHandler -ne $null)){
                            if ($hklm_wow64_clsid[$item].InProcHandler.tolower() -ne $hku_wow64_clsid[$item].InProcHandler.tolower()){
                                if ($hku_wow64_clsid[$item].ScriptletURL -ne $null){
                                    New-ComHijack -Hive HKU -SubKey $hku_wow64_clsid[$item].subkey -PreviousPath $hklm_wow64_clsid[$item].InProcHandler -ImagePath $hku_wow64_clsid[$item].InProcHandler -Arguments $hku_wow64_clsid[$item].ScriptletURL -PSComputerName $computerName
                                }
                                else{
                                    New-ComHijack -Hive HKU -SubKey $hku_wow64_clsid[$item].subkey -PreviousPath $hklm_wow64_clsid[$item].InProcHandler -ImagePath $hku_wow64_clsid[$item].InProcHandler -PSComputerName $computerName
                                }
                            }
                        }
                    }
                }

                #DEBUG timing
                #write-host "finished hku wow64 hijack comparison for $sid [$($timer.elapsed.minutes).$($timer.elapsed.seconds).$($timer.elapsed.milliseconds) seconds]"
            }
            $timer.Stop()
            #DEBUG timing
            write-host "finished everything for session [$($timer.elapsed.minutes).$($timer.elapsed.seconds).$($timer.elapsed.milliseconds) seconds]"
        }
    }
}
