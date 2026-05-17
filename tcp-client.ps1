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
    Write-Host "Connecting to ${Host}:${Port}..." -ForegroundColor Cyan
    $client = Connect-TCPClient -Host $Host -Port $Port -TimeoutMs $TimeoutMs
    $stream = $client.GetStream()
    $reader = New-Object System.IO.StreamReader($stream)
    $writer = New-Object System.IO.StreamWriter($stream)
    $writer.AutoFlush = $true

    Write-Host "Connected. Type messages and press Enter to send. Type 'exit' to quit." -ForegroundColor Green

    while ($client.Connected) {
        $input = Read-Host ">"

        if ($input -eq "exit") { break }

        $writer.WriteLine($input)

        if ($stream.DataAvailable) {
            $response = $reader.ReadLine()
            Write-Host "< $response" -ForegroundColor Yellow
        }
    }
}
catch {
    Write-Host "Error: $_" -ForegroundColor Red
}
finally {
    if ($writer) { $writer.Close() }
    if ($reader) { $reader.Close() }
    if ($client) { $client.Close() }
    Write-Host "Disconnected." -ForegroundColor Cyan
}
