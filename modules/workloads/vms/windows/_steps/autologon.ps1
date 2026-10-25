# Signs $Data.account on at boot with $Data.password, kept in the LSA secret
# that Sysinternals Autologon uses rather than in the registry; with
# $Data.enable false, removes both.
$winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class WorkloadsLsaSecret {
    [StructLayout(LayoutKind.Sequential)]
    struct UnicodeString { public ushort Length; public ushort MaximumLength; public IntPtr Buffer; }

    [StructLayout(LayoutKind.Sequential)]
    struct ObjectAttributes {
        public int Length; public IntPtr RootDirectory; public IntPtr ObjectName;
        public uint Attributes; public IntPtr SecurityDescriptor; public IntPtr SecurityQualityOfService;
    }

    [DllImport("advapi32.dll")]
    static extern uint LsaOpenPolicy(IntPtr system, ref ObjectAttributes attributes, uint access, out IntPtr policy);
    [DllImport("advapi32.dll")]
    static extern uint LsaStorePrivateData(IntPtr policy, ref UnicodeString key, IntPtr data);
    [DllImport("advapi32.dll")]
    static extern uint LsaRetrievePrivateData(IntPtr policy, ref UnicodeString key, out IntPtr data);
    [DllImport("advapi32.dll")]
    static extern uint LsaFreeMemory(IntPtr buffer);
    [DllImport("advapi32.dll")]
    static extern uint LsaClose(IntPtr policy);
    [DllImport("advapi32.dll")]
    static extern int LsaNtStatusToWinError(uint status);

    const uint PolicyGetPrivateInformation = 0x4;
    const uint PolicyCreateSecret = 0x20;
    const uint StatusObjectNameNotFound = 0xC0000034;

    static UnicodeString Wrap(string value) {
        UnicodeString result;
        result.Length = (ushort)(value.Length * 2);
        result.MaximumLength = (ushort)(result.Length + 2);
        result.Buffer = Marshal.StringToHGlobalUni(value);
        return result;
    }

    static void Check(uint status, string call) {
        if (status != 0) {
            throw new System.ComponentModel.Win32Exception(LsaNtStatusToWinError(status), call + " failed");
        }
    }

    static IntPtr Open(uint access) {
        ObjectAttributes attributes = new ObjectAttributes();
        IntPtr policy;
        Check(LsaOpenPolicy(IntPtr.Zero, ref attributes, access, out policy), "LsaOpenPolicy");
        return policy;
    }

    // A deleted secret reads back empty, so empty counts as absent.
    public static string Read(string name) {
        IntPtr policy = Open(PolicyGetPrivateInformation);
        UnicodeString key = Wrap(name);
        try {
            IntPtr data;
            uint status = LsaRetrievePrivateData(policy, ref key, out data);
            if (status == StatusObjectNameNotFound) { return null; }
            Check(status, "LsaRetrievePrivateData");
            if (data == IntPtr.Zero) { return null; }
            try {
                UnicodeString value = (UnicodeString)Marshal.PtrToStructure(data, typeof(UnicodeString));
                if (value.Length == 0) { return null; }
                return Marshal.PtrToStringUni(value.Buffer, value.Length / 2);
            } finally {
                LsaFreeMemory(data);
            }
        } finally {
            Marshal.FreeHGlobal(key.Buffer);
            LsaClose(policy);
        }
    }

    // A null value deletes the secret.
    public static void Write(string name, string value) {
        IntPtr policy = Open(PolicyCreateSecret);
        UnicodeString key = Wrap(name);
        IntPtr data = IntPtr.Zero;
        UnicodeString wrapped = new UnicodeString();
        try {
            if (value != null) {
                wrapped = Wrap(value);
                data = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(UnicodeString)));
                Marshal.StructureToPtr(wrapped, data, false);
            }
            uint status = LsaStorePrivateData(policy, ref key, data);
            if (value == null && status == StatusObjectNameNotFound) { return; }
            Check(status, "LsaStorePrivateData");
        } finally {
            if (data != IntPtr.Zero) { Marshal.FreeHGlobal(data); }
            if (wrapped.Buffer != IntPtr.Zero) { Marshal.FreeHGlobal(wrapped.Buffer); }
            Marshal.FreeHGlobal(key.Buffer);
            LsaClose(policy);
        }
    }
}
'@

function Get-Value([string] $name) {
    (Get-Item -Path $winlogon).GetValue($name)
}

function Test-InPlace {
    # A plain-text DefaultPassword would win over the LSA secret, and a set
    # AutoLogonCount turns autologon off once it runs out.
    if ($null -ne (Get-Value 'DefaultPassword') -or $null -ne (Get-Value 'AutoLogonCount')) { return $false }
    $secret = [WorkloadsLsaSecret]::Read('DefaultPassword')
    if (-not $Data.enable) { return "$(Get-Value 'AutoAdminLogon')" -ne '1' -and $null -eq $secret }
    "$(Get-Value 'AutoAdminLogon')" -eq '1' -and
    "$(Get-Value 'DefaultUserName')" -eq $Data.account -and
    "$(Get-Value 'DefaultDomainName')" -eq $env:COMPUTERNAME -and
    $secret -ceq $Data.password
}

if ($Mode -eq 'probe') {
    if (Test-InPlace) { exit 0 }
    exit 10
}
foreach ($name in 'DefaultPassword', 'AutoLogonCount') {
    if ($null -ne (Get-Value $name)) { Remove-ItemProperty -Path $winlogon -Name $name }
}
if ($Data.enable) {
    [WorkloadsLsaSecret]::Write('DefaultPassword', $Data.password)
    Set-ItemProperty -Path $winlogon -Name DefaultUserName -Value $Data.account
    Set-ItemProperty -Path $winlogon -Name DefaultDomainName -Value $env:COMPUTERNAME
    Set-ItemProperty -Path $winlogon -Name AutoAdminLogon -Value '1'
}
else {
    Set-ItemProperty -Path $winlogon -Name AutoAdminLogon -Value '0'
    [WorkloadsLsaSecret]::Write('DefaultPassword', $null)
}
