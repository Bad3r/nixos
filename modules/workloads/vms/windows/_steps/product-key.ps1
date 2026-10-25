# The SoftwareLicensingService calls behind `slmgr.vbs /ipk` and `/ato`; the
# key arrives on stdin, so no command line in the guest carries it.
$key = $Data.key
$windowsApplication = '55c92734-d682-4d71-983e-d6ec3f16059f'

function Get-Product {
    Get-CimInstance -ClassName SoftwareLicensingProduct `
        -Filter "ApplicationID = '$windowsApplication' AND PartialProductKey IS NOT NULL" |
        Select-Object -First 1
}

$product = Get-Product
$installed = $product -and $product.PartialProductKey -eq $key.Substring($key.Length - 5)
if ($Mode -eq 'probe') {
    if ($installed -and $product.LicenseStatus -eq 1) { exit 0 }
    exit 10
}
if (-not $installed) {
    $service = Get-CimInstance -ClassName SoftwareLicensingService
    Invoke-CimMethod -InputObject $service -MethodName InstallProductKey -Arguments @{ ProductKey = $key } | Out-Null
    Invoke-CimMethod -InputObject $service -MethodName RefreshLicenseStatus | Out-Null
    $product = Get-Product
}
Invoke-CimMethod -InputObject $product -MethodName Activate | Out-Null
