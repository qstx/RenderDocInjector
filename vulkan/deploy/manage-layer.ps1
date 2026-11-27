param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Register', 'Unregister')]
    [string]$Action
)

$ErrorActionPreference = 'Stop'
$layerKey = 'SOFTWARE\Khronos\Vulkan\ImplicitLayers'
$stateKey = 'SOFTWARE\RenderDocInjector\VulkanLayer'
$manifest = Join-Path $PSScriptRoot 'renderdoc-layer-ungated.json'
$dword = [Microsoft.Win32.RegistryValueKind]::DWord

function Get-EnabledOfficialLayers($layers) {
    if ($null -ne $layers) {
        $layers.GetValueNames() | Where-Object {
            [IO.Path]::GetFileName($_) -ieq 'renderdoc.json' -and
            $layers.GetValueKind($_) -eq $dword -and $layers.GetValue($_) -eq 0
        }
    }
}

function Restore-OfficialLayers($layers, $state) {
    if ($null -eq $state) { return }
    if ($null -ne $layers) {
        foreach ($path in $state.GetValue($manifest, [string[]]@())) {
            if ($layers.GetValue($path) -eq 1 -and $layers.GetValueKind($path) -eq $dword) {
                $layers.SetValue($path, 0, $dword)
            }
        }
    }
    $state.DeleteValue($manifest, $false)
}

try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Administrator rights required. Run the batch file from an elevated command prompt.'
    }

    $machine = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64')
    $user = [Microsoft.Win32.RegistryKey]::OpenBaseKey('CurrentUser', 'Registry64')
    $userLayers = $user.OpenSubKey($layerKey, $true)

    if ($Action -eq 'Register') {
        if (!(Test-Path -LiteralPath $manifest -PathType Leaf)) {
            throw 'Manifest not found. Run python tools\gen_manifest.py first.'
        }
        $layer = (Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json).layer
        if ($layer.name -cne 'VK_LAYER_RENDERDOC_Capture_Ungated' -or $null -ne $layer.enable_environment -or
            !$layer.library_path -or ![IO.Path]::IsPathRooted($layer.library_path) -or
            !(Test-Path -LiteralPath $layer.library_path -PathType Leaf)) {
            throw 'Unexpected manifest or DLL path. Re-run python tools\gen_manifest.py.'
        }
        if (@(Get-EnabledOfficialLayers $userLayers).Count) {
            throw 'An official RenderDoc layer is enabled in HKCU. Disable that registration before proceeding.'
        }

        $layers = $machine.CreateSubKey($layerKey)
        $state = $machine.CreateSubKey($stateKey)
        if (@($state.GetValueNames() | Where-Object { $_ -ine $manifest }).Count) {
            throw 'Another checkout manages this Vulkan layer. Run its unregister-layer.bat first.'
        }

        $enabled = @(Get-EnabledOfficialLayers $layers)
        $previous = @($state.GetValue($manifest, [string[]]@()))
        $backup = [string[]](@($previous + $enabled | Select-Object -Unique))
        $state.SetValue($manifest, $backup, [Microsoft.Win32.RegistryValueKind]::MultiString)
        try {
            $layers.DeleteValue($manifest, $false)
            if ($null -ne $userLayers) { $userLayers.DeleteValue($manifest, $false) }
            foreach ($path in $enabled) { $layers.SetValue($path, 1, $dword) }
            $layers.SetValue($manifest, 0, $dword)
        } catch {
            $layers.DeleteValue($manifest, $false)
            Restore-OfficialLayers $layers $state
            throw
        }
        Write-Host 'Registered the 64-bit ungated layer. Run unregister-layer.bat as administrator after capture.'
    } else {
        $layers = $machine.OpenSubKey($layerKey, $true)
        $state = $machine.OpenSubKey($stateKey, $true)
        if ($null -ne $userLayers) { $userLayers.DeleteValue($manifest, $false) }
        if ($null -ne $layers) { $layers.DeleteValue($manifest, $false) }
        Restore-OfficialLayers $layers $state
        Write-Host 'Removed the ungated layer and restored any saved RenderDoc registrations.'
    }
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
