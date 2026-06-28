#Requires -Version 5.1
Set-StrictMode -Version Latest

#region Funciones internas

function ConvertTo-IPv4Address {
    param(
        [Parameter(Mandatory = $true)][string]$Address,
        [string]$FieldName = 'Direccion IPv4'
    )

    if ($Address -notmatch '^\d{1,3}(?:\.\d{1,3}){3}$') {
        throw "$FieldName invalida: '$Address'. Use notacion decimal punteada, por ejemplo 192.168.1.10."
    }

    $parsed = $null
    if (-not [System.Net.IPAddress]::TryParse($Address, [ref]$parsed) -or
        $parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw "$FieldName invalida: '$Address'."
    }

    $octets = $Address.Split('.') | ForEach-Object { [int]$_ }
    if (@($octets | Where-Object { $_ -lt 0 -or $_ -gt 255 }).Count -gt 0) {
        throw "$FieldName invalida: '$Address'. Cada octeto debe estar entre 0 y 255."
    }

    return $parsed
}

function ConvertTo-BinaryIP {
    param([Parameter(Mandatory = $true)][System.Net.IPAddress]$IP)
    ($IP.GetAddressBytes() | ForEach-Object { [Convert]::ToString($_, 2).PadLeft(8, '0') }) -join '.'
}

function ConvertTo-IntFromIP {
    param([Parameter(Mandatory = $true)][System.Net.IPAddress]$IP)

    if ($IP.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw "Solo se admiten direcciones IPv4."
    }

    $bytes = $IP.GetAddressBytes()
    [uint32](
        ([uint64]$bytes[0] * 16777216) +
        ([uint64]$bytes[1] * 65536) +
        ([uint64]$bytes[2] * 256) +
        [uint64]$bytes[3]
    )
}

function ConvertTo-IPFromInt {
    param([Parameter(Mandatory = $true)][uint32]$Int)

    [System.Net.IPAddress]([byte[]]@(
        ([uint64]$Int -shr 24) -band 0xFF
        ([uint64]$Int -shr 16) -band 0xFF
        ([uint64]$Int -shr 8)  -band 0xFF
        ([uint64]$Int          -band 0xFF)
    ))
}

function ConvertTo-PrefixFromMask {
    param([Parameter(Mandatory = $true)][System.Net.IPAddress]$Mask)

    $binary = ($Mask.GetAddressBytes() | ForEach-Object { [Convert]::ToString($_, 2).PadLeft(8, '0') }) -join ''
    if ($binary -notmatch '^1*0*$') {
        throw "Mascara no valida: '$Mask'. Los bits en 1 deben ser contiguos."
    }

    return @($binary.ToCharArray() | Where-Object { $_ -eq '1' }).Count
}

function ConvertTo-MaskFromPrefix {
    param([Parameter(Mandatory = $true)][int]$Prefix)

    if ($Prefix -lt 0 -or $Prefix -gt 32) {
        throw "Prefijo invalido: $Prefix. Debe estar entre 0 y 32."
    }

    if ($Prefix -eq 0) {
        return [System.Net.IPAddress]'0.0.0.0'
    }

    $hostBits    = 32 - $Prefix
    $wildcardInt = ([uint64]1 -shl $hostBits) - 1
    $maskInt     = [uint32]([uint64][uint32]::MaxValue - $wildcardInt)
    ConvertTo-IPFromInt -Int $maskInt
}

function Get-IPClass {
    param([Parameter(Mandatory = $true)][System.Net.IPAddress]$IP)

    $firstOctet = $IP.GetAddressBytes()[0]
    if ($firstOctet -le 127)                               { return 'A' }
    elseif ($firstOctet -le 191)                           { return 'B' }
    elseif ($firstOctet -le 223)                           { return 'C' }
    elseif ($firstOctet -le 239)                           { return 'D (Multicast)' }
    else                                                    { return 'E (Reservada)' }
}

function Test-IPInRange {
    param(
        [Parameter(Mandatory = $true)][uint32]$IP,
        [Parameter(Mandatory = $true)][string]$Start,
        [Parameter(Mandatory = $true)][string]$End
    )

    $startInt = ConvertTo-IntFromIP -IP (ConvertTo-IPv4Address -Address $Start)
    $endInt   = ConvertTo-IntFromIP -IP (ConvertTo-IPv4Address -Address $End)
    return ($IP -ge $startInt -and $IP -le $endInt)
}

function Get-IPType {
    param([Parameter(Mandatory = $true)][System.Net.IPAddress]$IP)

    $value = ConvertTo-IntFromIP -IP $IP

    if (Test-IPInRange -IP $value -Start '10.0.0.0'    -End '10.255.255.255')  { return 'Privada RFC1918' }
    if (Test-IPInRange -IP $value -Start '172.16.0.0'  -End '172.31.255.255')  { return 'Privada RFC1918' }
    if (Test-IPInRange -IP $value -Start '192.168.0.0' -End '192.168.255.255') { return 'Privada RFC1918' }
    if (Test-IPInRange -IP $value -Start '127.0.0.0'   -End '127.255.255.255') { return 'Loopback' }
    if (Test-IPInRange -IP $value -Start '169.254.0.0' -End '169.254.255.255') { return 'Link-local APIPA' }
    if (Test-IPInRange -IP $value -Start '100.64.0.0'  -End '100.127.255.255') { return 'CGNAT RFC6598' }
    if (Test-IPInRange -IP $value -Start '224.0.0.0'   -End '239.255.255.255') { return 'Multicast' }
    if (Test-IPInRange -IP $value -Start '240.0.0.0'   -End '255.255.255.255') { return 'Reservada' }

    return 'Publica'
}

function Test-PrivateIP {
    param([Parameter(Mandatory = $true)][System.Net.IPAddress]$IP)
    return ((Get-IPType -IP $IP) -eq 'Privada RFC1918')
}

function Get-ReverseDNSInfo {
    param(
        [Parameter(Mandatory = $true)][System.Net.IPAddress]$NetworkIP,
        [Parameter(Mandatory = $true)][int]$Prefix
    )

    $octets = $NetworkIP.ToString().Split('.')

    if ($Prefix -eq 0) {
        return [PSCustomObject]@{
            Zone = 'in-addr.arpa'
            Note = 'Zona raiz IPv4 reversa.'
        }
    }

    if (($Prefix % 8) -ne 0) {
        return [PSCustomObject]@{
            Zone = $null
            Note = "El prefijo /$Prefix no esta alineado a octetos. Requiere delegacion classless, normalmente RFC 2317."
        }
    }

    $octetCount = [int]($Prefix / 8)
    $zoneParts  = @($octets[0..($octetCount - 1)])
    [array]::Reverse($zoneParts)

    return [PSCustomObject]@{
        Zone = (($zoneParts -join '.') + '.in-addr.arpa')
        Note = if ($Prefix -eq 32) { 'Nombre reverso completo del host; normalmente contiene un registro PTR.' } else { 'Zona reversa alineada a octetos.' }
    }
}

function Get-NetworkRange {
    param([Parameter(Mandatory = $true)][string]$CIDR)

    if ($CIDR -notmatch '^(\d{1,3}(?:\.\d{1,3}){3})/(\d{1,2})$') {
        throw "CIDR invalido: '$CIDR'. Use el formato 192.168.1.0/24."
    }

    $ip     = ConvertTo-IPv4Address -Address $Matches[1]
    $prefix = [int]$Matches[2]
    $mask   = ConvertTo-MaskFromPrefix -Prefix $prefix
    $ipInt  = ConvertTo-IntFromIP -IP $ip
    $maskInt = ConvertTo-IntFromIP -IP $mask
    $wildcardInt = [uint32]([uint64][uint32]::MaxValue - [uint64]$maskInt)
    $networkInt  = [uint32]([uint64]$ipInt -band [uint64]$maskInt)
    $broadcastInt = [uint32]([uint64]$networkInt -bor [uint64]$wildcardInt)

    [PSCustomObject]@{
        IP           = $ip
        Prefix       = $prefix
        Mask         = $mask
        NetworkInt   = $networkInt
        BroadcastInt = $broadcastInt
        Network      = (ConvertTo-IPFromInt -Int $networkInt)
        Broadcast    = (ConvertTo-IPFromInt -Int $broadcastInt)
    }
}

#endregion

#region Funcion principal

function Invoke-IPCalc {
    <#
    .SYNOPSIS
        Calcula informacion detallada de una red IPv4.
    .EXAMPLE
        Invoke-IPCalc -Network 192.168.1.100/24
    .EXAMPLE
        Invoke-IPCalc -Network 10.0.0.1 -Mask 255.0.0.0
    .EXAMPLE
        ipcalc 172.16.0.0/22 -SplitSubnets 4
    .EXAMPLE
        ipcalc 192.168.1.0/24 -CompareWith 192.168.1.128/25
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Network,

        [Parameter(Position = 1)]
        [string]$Mask,

        [Parameter()]
        [ValidateRange(1, 65536)]
        [int]$SplitSubnets,

        [Parameter()]
        [string]$CompareWith,

        [Parameter()]
        [switch]$NoColor
    )

    $inputIP    = $null
    $prefix     = $null
    $subnetMask = $null

    if ($Network -match '^(\d{1,3}(?:\.\d{1,3}){3})/(\d{1,2})$') {
        if ($PSBoundParameters.ContainsKey('Mask')) {
            throw 'No combine un prefijo CIDR con el parametro -Mask.'
        }

        $inputIP    = ConvertTo-IPv4Address -Address $Matches[1]
        $prefix     = [int]$Matches[2]
        $subnetMask = ConvertTo-MaskFromPrefix -Prefix $prefix
    }
    elseif ($Network -match '^\d{1,3}(?:\.\d{1,3}){3}$') {
        $inputIP = ConvertTo-IPv4Address -Address $Network
        if ($PSBoundParameters.ContainsKey('Mask')) {
            $subnetMask = ConvertTo-IPv4Address -Address $Mask -FieldName 'Mascara'
            $prefix     = ConvertTo-PrefixFromMask -Mask $subnetMask
        }
        else {
            $prefix     = 32
            $subnetMask = ConvertTo-MaskFromPrefix -Prefix 32
        }
    }
    else {
        throw 'Formato invalido. Use: 192.168.1.1/24 o 192.168.1.1 -Mask 255.255.255.0.'
    }

    $ipInt         = ConvertTo-IntFromIP -IP $inputIP
    $maskInt       = ConvertTo-IntFromIP -IP $subnetMask
    $wildcardInt   = [uint32]([uint64][uint32]::MaxValue - [uint64]$maskInt)
    $networkInt    = [uint32]([uint64]$ipInt -band [uint64]$maskInt)
    $broadcastInt  = [uint32]([uint64]$networkInt -bor [uint64]$wildcardInt)

    $networkIP     = ConvertTo-IPFromInt -Int $networkInt
    $broadcastIP   = ConvertTo-IPFromInt -Int $broadcastInt
    $wildcardIP    = ConvertTo-IPFromInt -Int $wildcardInt

    $totalHosts    = [uint64][Math]::Pow(2, 32 - $prefix)
    $usableHosts   = if ($prefix -ge 31) { $totalHosts } else { [uint64]($totalHosts - 2) }
    $firstHost     = if ($prefix -lt 31) { ConvertTo-IPFromInt -Int ([uint32]([uint64]$networkInt + 1)) } else { $networkIP }
    $lastHost      = if ($prefix -lt 31) { ConvertTo-IPFromInt -Int ([uint32]([uint64]$broadcastInt - 1)) } else { $broadcastIP }

    $ipClass       = Get-IPClass -IP $inputIP
    $ipType        = Get-IPType -IP $inputIP
    $isPrivate     = Test-PrivateIP -IP $inputIP
    $reverseDNS    = Get-ReverseDNSInfo -NetworkIP $networkIP -Prefix $prefix

    $ipBin         = ConvertTo-BinaryIP -IP $inputIP
    $maskBin       = ConvertTo-BinaryIP -IP $subnetMask
    $networkBin    = ConvertTo-BinaryIP -IP $networkIP
    $broadcastBin  = ConvertTo-BinaryIP -IP $broadcastIP

    $esc = [char]27
    if ($NoColor) {
        $cLabel = $cValue = $cBin = $cGood = $cDim = $cReset = $cHeader = $cRed = ''
    }
    else {
        $cLabel  = "$esc[36m"
        $cValue  = "$esc[97m"
        $cBin    = "$esc[33m"
        $cGood   = "$esc[32m"
        $cDim    = "$esc[90m"
        $cReset  = "$esc[0m"
        $cHeader = "$esc[1;35m"
        $cRed    = "$esc[31m"
    }

    function Write-Row {
        param(
            [string]$Label,
            [string]$Value,
            [string]$Binary = '',
            [string]$ValueColor = $cValue
        )
        $lbl = "$cLabel$($Label.PadRight(24))$cReset"
        $val = "$ValueColor$($Value.PadRight(28))$cReset"
        $bin = if ($Binary) { "$cBin$Binary$cReset" } else { '' }
        Write-Host "$lbl $val $bin"
    }

    Write-Host ''
    Write-Host "$cHeader-------------------------------------------------------------$cReset"
    Write-Host "$cHeader  IPCalc PowerShell - Red: $networkIP/$prefix$cReset"
    Write-Host "$cHeader-------------------------------------------------------------$cReset"
    Write-Host ''

    Write-Row -Label 'Direccion:'         -Value "$inputIP"              -Binary $ipBin
    Write-Row -Label 'Mascara de red:'    -Value "$subnetMask /$prefix"  -Binary $maskBin
    Write-Row -Label 'Wildcard:'          -Value "$wildcardIP"
    Write-Host ''
    Write-Row -Label 'Red:'               -Value "$networkIP/$prefix"    -Binary $networkBin   -ValueColor $cGood
    Write-Row -Label 'Broadcast:'         -Value "$broadcastIP"          -Binary $broadcastBin -ValueColor $cRed
    Write-Host ''
    Write-Row -Label 'Primer host:'       -Value "$firstHost"
    Write-Row -Label 'Ultimo host:'       -Value "$lastHost"
    Write-Row -Label 'Hosts totales:'     -Value ('{0:N0}' -f $totalHosts)
    Write-Row -Label 'Hosts utilizables:' -Value ('{0:N0}' -f $usableHosts)
    Write-Host ''
    Write-Row -Label 'Clase historica:'   -Value $ipClass
    Write-Row -Label 'Tipo:'              -Value $ipType
    Write-Row -Label 'Zona reversa DNS:'  -Value $(if ($reverseDNS.Zone) { $reverseDNS.Zone } else { 'No directa' })
    Write-Row -Label 'Nota DNS reversa:'  -Value $reverseDNS.Note
    Write-Host ''
    Write-Host "$cDim-------------------------------------------------------------$cReset"

    if ($PSBoundParameters.ContainsKey('SplitSubnets')) {
        if (($SplitSubnets -band ($SplitSubnets - 1)) -ne 0) {
            throw 'SplitSubnets debe ser una potencia de 2: 1, 2, 4, 8, 16...'
        }

        $bits      = [int][Math]::Log($SplitSubnets, 2)
        $newPrefix = $prefix + $bits
        if ($newPrefix -gt 32) {
            throw "No es posible dividir la red en $SplitSubnets subredes: el prefijo resultante seria /$newPrefix."
        }

        $subnetCount = [uint32]$SplitSubnets
        $subnetSize  = [uint64][Math]::Pow(2, 32 - $newPrefix)

        Write-Host ''
        Write-Host "$cHeader  Division en $subnetCount subredes (/$newPrefix)$cReset"
        Write-Host ("$cDim  {0,-5}  {1,-22}  {2,-18}  {3,-16}  {4}$cReset" -f 'Sub#', 'Red', 'Broadcast', 'Primer Host', 'Ultimo Host')
        Write-Host "$cDim  -------------------------------------------------------------------------------$cReset"

        for ($i = 0; $i -lt $subnetCount; $i++) {
            $sNetInt64   = [uint64]$networkInt + ([uint64]$i * $subnetSize)
            $sBcastInt64 = $sNetInt64 + $subnetSize - 1
            $sNetInt     = [uint32]$sNetInt64
            $sBcastInt   = [uint32]$sBcastInt64

            if ($newPrefix -lt 31) {
                $sFirstInt = [uint32]($sNetInt64 + 1)
                $sLastInt  = [uint32]($sBcastInt64 - 1)
            }
            else {
                $sFirstInt = $sNetInt
                $sLastInt  = $sBcastInt
            }

            $sNet   = ConvertTo-IPFromInt -Int $sNetInt
            $sBcast = ConvertTo-IPFromInt -Int $sBcastInt
            $sFirst = ConvertTo-IPFromInt -Int $sFirstInt
            $sLast  = ConvertTo-IPFromInt -Int $sLastInt

            $rowColor = if ($i % 2 -eq 0) { $cValue } else { $cDim }
            Write-Host ("$rowColor  {0,-5}  {1,-22}  {2,-18}  {3,-16}  {4}$cReset" -f ($i + 1), "$sNet/$newPrefix", $sBcast, $sFirst, $sLast)
        }
        Write-Host ''
    }

    $comparison = $null
    if ($PSBoundParameters.ContainsKey('CompareWith')) {
        $comparison = Compare-IPNetwork `
            -Network1 "$networkIP/$prefix" `
            -Network2 $CompareWith `
            -NoColor:$NoColor
    }

    [PSCustomObject]@{
        InputAddress   = $inputIP.ToString()
        NetworkAddress = $networkIP.ToString()
        SubnetMask     = $subnetMask.ToString()
        Prefix         = $prefix
        Wildcard       = $wildcardIP.ToString()
        Broadcast      = $broadcastIP.ToString()
        FirstHost      = $firstHost.ToString()
        LastHost       = $lastHost.ToString()
        TotalHosts     = $totalHosts
        UsableHosts    = $usableHosts
        Class          = $ipClass
        Type           = $ipType
        IsPrivate      = $isPrivate
        ReverseDNSZone = $reverseDNS.Zone
        ReverseDNSNote  = $reverseDNS.Note
        CIDR            = "$networkIP/$prefix"
        ComparedNetwork = if ($null -ne $comparison) { $comparison.Network2 } else { $null }
        NetworksOverlap = if ($null -ne $comparison) { $comparison.Overlap } else { $null }
        NetworkRelation = if ($null -ne $comparison) { $comparison.Relation } else { $null }
    }
}

#endregion

#region Comparacion de redes

function Compare-IPNetwork {
    <#
    .SYNOPSIS
        Compara dos redes IPv4 y determina si se solapan o si una contiene a la otra.
    .EXAMPLE
        Compare-IPNetwork -Network1 10.0.0.0/8 -Network2 10.1.2.0/24
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Network1,
        [Parameter(Mandatory = $true)][string]$Network2,
        [Parameter()][switch]$NoColor
    )

    $r1 = Get-NetworkRange -CIDR $Network1
    $r2 = Get-NetworkRange -CIDR $Network2

    $overlap = $r1.NetworkInt -le $r2.BroadcastInt -and $r2.NetworkInt -le $r1.BroadcastInt
    $n1InN2  = $r1.NetworkInt -ge $r2.NetworkInt -and $r1.BroadcastInt -le $r2.BroadcastInt
    $n2InN1  = $r2.NetworkInt -ge $r1.NetworkInt -and $r2.BroadcastInt -le $r1.BroadcastInt

    $relation = if ($n1InN2 -and $n2InN1) {
        'Identicas'
    }
    elseif ($n1InN2) {
        'Network1 contenida en Network2'
    }
    elseif ($n2InN1) {
        'Network2 contenida en Network1'
    }
    elseif ($overlap) {
        'Solapadas'
    }
    else {
        'Independientes'
    }

    $esc = [char]27
    if ($NoColor) {
        $cHeader = $cDim = $cReset = $cGood = $cWarn = $cRed = $cValue = ''
    }
    else {
        $cHeader = "$esc[1;35m"
        $cDim    = "$esc[90m"
        $cReset  = "$esc[0m"
        $cGood   = "$esc[32m"
        $cWarn   = "$esc[33m"
        $cRed    = "$esc[31m"
        $cValue  = "$esc[97m"
    }

    Write-Host ''
    Write-Host "$cHeader  Comparacion de redes$cReset"
    Write-Host "$cDim  -----------------------------------------$cReset"
    Write-Host "  Red 1: $cValue$Network1$cReset"
    Write-Host "  Red 2: $cValue$Network2$cReset"
    Write-Host ''

    switch ($relation) {
        'Identicas'                       { Write-Host "  $cGood[OK] Las redes son identicas.$cReset" }
        'Network1 contenida en Network2' { Write-Host "  $cWarn[>>] $Network1 esta contenida dentro de $Network2.$cReset" }
        'Network2 contenida en Network1' { Write-Host "  $cWarn[>>] $Network2 esta contenida dentro de $Network1.$cReset" }
        'Solapadas'                       { Write-Host "  $cRed[!!] Las redes se solapan.$cReset" }
        'Independientes'                  { Write-Host "  $cGood[OK] Las redes no se solapan.$cReset" }
    }
    Write-Host ''

    [PSCustomObject]@{
        Network1 = "$($r1.Network)/$($r1.Prefix)"
        Network2 = "$($r2.Network)/$($r2.Prefix)"
        Overlap  = $overlap
        Relation = $relation
    }
}

#endregion

#region Validacion

function Test-IPAddress {
    <#
    .SYNOPSIS
        Valida si una cadena es una direccion IPv4 valida, con o sin prefijo CIDR.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string[]]$Address
    )

    process {
        foreach ($item in $Address) {
            $valid  = $false
            $reason = ''

            try {
                if ($item -match '^(\d{1,3}(?:\.\d{1,3}){3})(?:/(\d{1,2}))?$') {
                    $null = ConvertTo-IPv4Address -Address $Matches[1]
                    if ($Matches[2] -and [int]$Matches[2] -gt 32) {
                        throw 'El prefijo CIDR debe estar entre 0 y 32.'
                    }
                    $valid = $true
                }
                else {
                    throw 'No coincide con el formato IPv4 esperado.'
                }
            }
            catch {
                $reason = $_.Exception.Message
            }

            [PSCustomObject]@{
                Address = $item
                IsValid = $valid
                Reason  = if ($valid) { 'OK' } else { $reason }
            }
        }
    }
}

#endregion

#region Ayuda

function Show-IPCalcHelp {
    <#
    .SYNOPSIS
        Muestra ejemplos de uso del modulo IPCalc.
    #>
    [CmdletBinding()]
    param()

    @'
IPCalc PowerShell - Ayuda rapida
================================

1. Calcular una red usando CIDR
   ipcalc 192.168.1.100/24

2. Calcular una red usando mascara decimal
   ipcalc 10.20.30.40 -Mask 255.255.0.0

3. Dividir una red en subredes iguales
   ipcalc 172.16.0.0/22 -SplitSubnets 4

4. Verificar si dos redes se solapan
   ipcalc 192.168.1.0/24 -CompareWith 192.168.1.128/25

5. Comparar dos redes sin ejecutar el calculo completo
   Compare-IPNetwork -Network1 10.0.0.0/8 -Network2 10.20.30.0/24

6. Validar una direccion IPv4 o un CIDR
   Test-IPAddress 192.168.1.10/24

7. Validar varias direcciones
   '192.168.1.1', '999.1.1.1', '10.0.0.0/33' | Test-IPAddress

8. Mostrar esta ayuda
   Show-IPCalcHelp
   show-ipcalhelp
   sow-ipcalhelp

Parametros principales de ipcalc
--------------------------------
-Network       Direccion IPv4 o red CIDR. Es el primer argumento.
-Mask          Mascara decimal cuando Network no incluye prefijo CIDR.
-SplitSubnets  Cantidad de subredes iguales. Debe ser una potencia de 2.
-CompareWith   Segunda red CIDR para comprobar si existe solapamiento.
-NoColor       Desactiva los colores ANSI de la salida.
'@ | Write-Host
}

#endregion

Set-Alias -Name ipcalc         -Value Invoke-IPCalc
Set-Alias -Name show-ipcalhelp -Value Show-IPCalcHelp
Set-Alias -Name sow-ipcalhelp  -Value Show-IPCalcHelp
Set-Alias -Name ipcalhelp      -Value Show-IPCalcHelp

Export-ModuleMember `
    -Function Invoke-IPCalc, Compare-IPNetwork, Test-IPAddress, Show-IPCalcHelp `
    -Alias ipcalc, show-ipcalhelp, sow-ipcalhelp, ipcalhelp
