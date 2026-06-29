# IPCalc PowerShell

A lightweight IPv4 subnet calculator for PowerShell.

`IPCalc` calculates detailed IPv4 network information, splits networks into equal-sized subnets, compares CIDR ranges for overlap or containment, validates IPv4 addresses, and provides reverse DNS information.

The module writes a human-readable report to the console and also returns structured PowerShell objects that can be filtered, exported, or consumed by other scripts.

## Features

- Calculate IPv4 network details from CIDR notation or a decimal subnet mask.
- Display the network address, broadcast address, wildcard mask, host range, and host counts.
- Show binary representations of the address, mask, network, and broadcast address.
- Identify historical IPv4 address classes.
- Classify addresses as public, private, loopback, APIPA, CGNAT, multicast, or reserved.
- Generate reverse DNS information for octet-aligned prefixes.
- Split a network into equal-sized subnets.
- Compare two IPv4 networks for overlap or containment.
- Validate individual or multiple IPv4 addresses and CIDR values.
- Return structured objects for automation and pipeline processing.
- Support ANSI-colored output with a `-NoColor` option.

## Requirements

- Windows PowerShell 5.1 or later.
- PowerShell 7 is also compatible with the module's minimum version requirement.
- IPv4 only.

## Installation

### Import from the current directory

Place the module file in a directory and rename it to `IPCalc.psm1` if necessary:

```powershell
Import-Module .\IPCalc.psm1 -Force
```

Verify that the exported commands are available:

```powershell
Get-Command -Module IPCalc
```

### Install in a PowerShell module directory

Create an `IPCalc` directory inside one of the paths listed in `$env:PSModulePath`, then place the module file inside it:

```text
IPCalc/
└── IPCalc.psm1
```

For the current user on Windows PowerShell 5.1, a typical path is:

```text
$HOME\Documents\WindowsPowerShell\Modules\IPCalc\IPCalc.psm1
```

For PowerShell 7, a typical path is:

```text
$HOME\Documents\PowerShell\Modules\IPCalc\IPCalc.psm1
```

After installation, import it by name:

```powershell
Import-Module IPCalc
```

If Windows blocks the downloaded file, run:

```powershell
Unblock-File .\IPCalc.psm1
```

## Quick Start

Calculate a network using CIDR notation:

```powershell
ipcalc 192.168.1.100/24
```

Calculate a network using a decimal subnet mask:

```powershell
ipcalc 10.20.30.40 -Mask 255.255.0.0
```

Split a network into four equal-sized subnets:

```powershell
ipcalc 172.16.0.0/22 -SplitSubnets 4
```

Compare two networks:

```powershell
ipcalc 192.168.1.0/24 -CompareWith 192.168.1.128/25
```

Validate an IPv4 address or CIDR value:

```powershell
Test-IPAddress 192.168.1.10/24
```

Display the built-in quick help:

```powershell
Show-IPCalcHelp
```

## Exported Commands

### `Invoke-IPCalc`

Calculates detailed information about an IPv4 network.

```powershell
Invoke-IPCalc [-Network] <string> [[-Mask] <string>]
              [-SplitSubnets <int>]
              [-CompareWith <string>]
              [-NoColor]
```

The alias `ipcalc` can be used instead of `Invoke-IPCalc`.

#### Parameters

| Parameter | Description |
|---|---|
| `-Network` | IPv4 address, optionally followed by a CIDR prefix. Examples: `192.168.1.10` or `192.168.1.10/24`. |
| `-Mask` | Decimal subnet mask used when `-Network` does not contain a CIDR prefix. |
| `-SplitSubnets` | Number of equal-sized subnets to generate. The value must be a power of two between 1 and 65,536. |
| `-CompareWith` | A second CIDR network to compare with the calculated network. |
| `-NoColor` | Disables ANSI colors in the console output. |

#### Examples

```powershell
Invoke-IPCalc -Network 192.168.50.25/24
```

```powershell
Invoke-IPCalc -Network 10.10.20.30 -Mask 255.255.252.0
```

```powershell
Invoke-IPCalc -Network 10.0.0.0/16 -SplitSubnets 8
```

```powershell
Invoke-IPCalc -Network 10.0.0.0/24 -CompareWith 10.0.0.128/25
```

```powershell
Invoke-IPCalc -Network 192.168.1.0/24 -NoColor
```

#### Returned properties

`Invoke-IPCalc` returns a `PSCustomObject` with the following properties:

| Property | Description |
|---|---|
| `InputAddress` | Original IPv4 address supplied to the command. |
| `NetworkAddress` | Calculated network address. |
| `SubnetMask` | Decimal subnet mask. |
| `Prefix` | CIDR prefix length. |
| `Wildcard` | Wildcard mask. |
| `Broadcast` | Broadcast address. |
| `FirstHost` | First usable address, or the first address for `/31` and `/32`. |
| `LastHost` | Last usable address, or the last address for `/31` and `/32`. |
| `TotalHosts` | Total number of addresses in the network. |
| `UsableHosts` | Number of usable addresses. |
| `Class` | Historical IPv4 class. |
| `Type` | Address classification. |
| `IsPrivate` | Indicates whether the input is an RFC 1918 private address. |
| `ReverseDNSZone` | Reverse DNS zone or reverse host name when directly derivable. |
| `ReverseDNSNote` | Additional reverse DNS guidance. |
| `CIDR` | Normalized network in CIDR notation. |
| `ComparedNetwork` | Normalized comparison network, when `-CompareWith` is used. |
| `NetworksOverlap` | Indicates whether the two networks overlap. |
| `NetworkRelation` | Describes containment, equality, overlap, or independence. |

### `Compare-IPNetwork`

Compares two IPv4 CIDR networks and determines their relationship.

```powershell
Compare-IPNetwork -Network1 <string> -Network2 <string> [-NoColor]
```

Possible relationships include:

- Identical networks.
- `Network1` contained in `Network2`.
- `Network2` contained in `Network1`.
- Partially overlapping networks.
- Independent networks.

Example:

```powershell
Compare-IPNetwork -Network1 10.0.0.0/8 -Network2 10.20.30.0/24
```

Use the returned object in conditional logic:

```powershell
$result = Compare-IPNetwork -Network1 192.168.1.0/24 -Network2 192.168.2.0/24 -NoColor

if ($result.Overlap) {
    Write-Warning 'The networks overlap.'
}
else {
    Write-Host 'The networks do not overlap.'
}
```

### `Test-IPAddress`

Validates IPv4 addresses with or without CIDR prefixes.

```powershell
Test-IPAddress -Address <string[]>
```

Validate one value:

```powershell
Test-IPAddress 192.168.1.10/24
```

Validate multiple values through the pipeline:

```powershell
'192.168.1.1', '999.1.1.1', '10.0.0.0/33' | Test-IPAddress
```

Example result:

```text
Address          IsValid Reason
-------          ------- ------
192.168.1.1          True OK
999.1.1.1           False Invalid IPv4 address...
10.0.0.0/33         False The CIDR prefix must be between 0 and 32.
```

The exact validation messages currently produced by the module are in Spanish.

### `Show-IPCalcHelp`

Displays a compact list of command examples and parameters:

```powershell
Show-IPCalcHelp
```

The following aliases are also exported:

```powershell
show-ipcalhelp
sow-ipcalhelp
ipcalhelp
```

## Automation Examples

### Capture the result without losing the console report

```powershell
$network = ipcalc 192.168.10.50/24

$network.NetworkAddress
$network.Broadcast
$network.UsableHosts
```

### Export calculation results to CSV

```powershell
$results = @(
    ipcalc 10.0.0.1/24 -NoColor
    ipcalc 172.16.10.1/23 -NoColor
    ipcalc 192.168.50.1/26 -NoColor
)

$results | Export-Csv .\ipcalc-results.csv -NoTypeInformation
```

### Validate a text file containing addresses

```powershell
Get-Content .\addresses.txt |
    Test-IPAddress |
    Where-Object IsValid -eq $false
```

### Check several networks for overlap

```powershell
$referenceNetwork = '10.0.0.0/16'

'10.0.10.0/24', '10.1.0.0/24', '192.168.1.0/24' |
    ForEach-Object {
        Compare-IPNetwork -Network1 $referenceNetwork -Network2 $_ -NoColor
    }
```

## Address Classification

The module recognizes the following IPv4 categories:

| Range or category | Reported type |
|---|---|
| `10.0.0.0/8` | Private RFC1918 |
| `172.16.0.0/12` | Private RFC1918 |
| `192.168.0.0/16` | Private RFC1918 |
| `127.0.0.0/8` | Loopback |
| `169.254.0.0/16` | Link-local APIPA |
| `100.64.0.0/10` | CGNAT RFC6598 |
| `224.0.0.0/4` | Multicast |
| `240.0.0.0/4` | Reserved |
| Other addresses | Public |

## Reverse DNS Behavior

For prefixes aligned to complete octets, the module calculates the corresponding `in-addr.arpa` name directly.

Examples:

| Network | Reverse DNS result |
|---|---|
| `192.168.1.0/24` | `1.168.192.in-addr.arpa` |
| `10.20.0.0/16` | `20.10.in-addr.arpa` |
| `10.0.0.0/8` | `10.in-addr.arpa` |

Prefixes that are not divisible by eight normally require classless reverse DNS delegation, commonly implemented according to RFC 2317. In those cases, the module returns an explanatory note instead of a direct zone name.

## Notes and Limitations

- The module supports IPv4 only; IPv6 is not implemented.
- `-Network` cannot contain a CIDR prefix when `-Mask` is also supplied.
- `-SplitSubnets` must be a power of two.
- Network values passed to `Compare-IPNetwork` are normalized before comparison.
- `/31` and `/32` networks are handled without subtracting network and broadcast addresses from the usable count.
- Console labels, built-in help, relationship descriptions, and error messages are currently written in Spanish.
- ANSI colors may depend on the terminal host. Use `-NoColor` when redirecting output or using a terminal without ANSI support.

## Module Exports

Functions:

```text
Invoke-IPCalc
Compare-IPNetwork
Test-IPAddress
Show-IPCalcHelp
```

Aliases:

```text
ipcalc
show-ipcalhelp
sow-ipcalhelp
ipcalhelp
```

## Contributing

Contributions are welcome. Suggested improvements include:

- IPv6 support.
- English and Spanish localization.
- Additional reserved-range classification.
- Pester tests.
- A PowerShell module manifest (`.psd1`).
- PowerShell Gallery packaging.

When submitting changes, keep public command output and returned object properties backward compatible whenever possible.

## License

No license is included in the current module file. Add a `LICENSE` file before publishing the repository if you want to define how others may use, modify, or redistribute the project.

---

## 👤 Author / Autor

**Luis Leonel Gomez Alvarez**

Copyright © 2026 Luis Leonel Gomez Alvarez

[LinkedIn](https://www.linkedin.com/in/luis-leonel-gomez-alvarez-b2aaba237)

---
