# Renders autounattend.xml for one Windows guest. Setup finds it at the root
# of the seed CD-ROM and loads the drivers from its $WinPEDriver$ directory.
{ lib }:
{
  computerName,
  accountName,
  edition,
  locale,
  timeZone,
  firstLogonCommand,
}:
let
  element = name: attrs: content: { inherit name attrs content; };

  renderAttrs =
    attrs: lib.concatMapAttrsStringSep "" (key: value: " ${key}=\"${lib.escapeXML value}\"") attrs;

  render =
    node:
    let
      open = "<${node.name}${renderAttrs node.attrs}>";
    in
    if builtins.isList node.content then
      "${open}${lib.concatMapStrings render node.content}</${node.name}>"
    else
      "${open}${lib.escapeXML node.content}</${node.name}>";

  leaf = name: value: element name { } value;
  node = name: children: element name { } children;
  added = name: children: element name { "wcm:action" = "add"; } children;

  component =
    name: children:
    element "component" {
      inherit name;
      processorArchitecture = "amd64";
      publicKeyToken = "31bf3856ad364e35";
      language = "neutral";
      versionScope = "nonSxS";
    } children;

  pass = name: components: element "settings" { pass = name; } components;

  locales = [
    (leaf "InputLocale" locale)
    (leaf "SystemLocale" locale)
    (leaf "UILanguage" locale)
    (leaf "UserLocale" locale)
  ];

  # Windows accepts a blank password only from the console, never over the network.
  blankPassword = node "Password" [
    (leaf "Value" "")
    (leaf "PlainText" "true")
  ];

  partition =
    order: type: extra:
    added "CreatePartition" (
      [
        (leaf "Order" (toString order))
        (leaf "Type" type)
      ]
      ++ extra
    );

  windowsPE = pass "windowsPE" [
    (component "Microsoft-Windows-International-Core-WinPE" (
      [ (node "SetupUILanguage" [ (leaf "UILanguage" locale) ]) ] ++ locales
    ))
    (component "Microsoft-Windows-Setup" [
      (node "DiskConfiguration" [
        (added "Disk" [
          (leaf "DiskID" "0")
          (leaf "WillWipeDisk" "true")
          (node "CreatePartitions" [
            (partition 1 "EFI" [ (leaf "Size" "300") ])
            (partition 2 "MSR" [ (leaf "Size" "16") ])
            (partition 3 "Primary" [ (leaf "Extend" "true") ])
          ])
          (node "ModifyPartitions" [
            (added "ModifyPartition" [
              (leaf "Order" "1")
              (leaf "PartitionID" "1")
              (leaf "Format" "FAT32")
              (leaf "Label" "System")
            ])
            (added "ModifyPartition" [
              (leaf "Order" "2")
              (leaf "PartitionID" "3")
              (leaf "Format" "NTFS")
              (leaf "Label" "Windows")
              (leaf "Letter" "C")
            ])
          ])
        ])
      ])
      (node "ImageInstall" [
        (node "OSImage" [
          (node "InstallFrom" [
            (added "MetaData" [
              (leaf "Key" "/IMAGE/NAME")
              (leaf "Value" edition)
            ])
          ])
          (node "InstallTo" [
            (leaf "DiskID" "0")
            (leaf "PartitionID" "3")
          ])
        ])
      ])
      (node "UserData" [ (leaf "AcceptEula" "true") ])
    ])
  ];

  specialize = pass "specialize" [
    (component "Microsoft-Windows-Shell-Setup" [
      (leaf "ComputerName" computerName)
      (leaf "TimeZone" timeZone)
    ])
    (component "Microsoft-Windows-SecureStartup-FilterDriver" [
      (leaf "PreventDeviceEncryption" "true")
    ])
  ];

  oobeSystem = pass "oobeSystem" [
    (component "Microsoft-Windows-International-Core" locales)
    (component "Microsoft-Windows-Shell-Setup" [
      (node "OOBE" [
        (leaf "HideEULAPage" "true")
        (leaf "HideLocalAccountScreen" "true")
        (leaf "HideOEMRegistrationScreen" "true")
        (leaf "HideOnlineAccountScreens" "true")
        (leaf "HideWirelessSetupInOOBE" "true")
        (leaf "ProtectYourPC" "3")
      ])
      (node "UserAccounts" [
        (node "LocalAccounts" [
          (added "LocalAccount" [
            (leaf "Name" accountName)
            (leaf "Group" "Administrators")
            blankPassword
          ])
        ])
      ])
      (node "AutoLogon" [
        (leaf "Username" accountName)
        (leaf "Enabled" "true")
        (leaf "LogonCount" "1")
        blankPassword
      ])
      (node "FirstLogonCommands" [
        (added "SynchronousCommand" [
          (leaf "Order" "1")
          (leaf "CommandLine" firstLogonCommand)
          (leaf "Description" "Workloads first logon")
        ])
      ])
    ])
  ];
in
''
  <?xml version="1.0" encoding="utf-8"?>
  ${render (
    element "unattend"
      {
        xmlns = "urn:schemas-microsoft-com:unattend";
        "xmlns:wcm" = "http://schemas.microsoft.com/WMIConfig/2002/State";
      }
      [
        windowsPE
        specialize
        oobeSystem
      ]
  )}
''
