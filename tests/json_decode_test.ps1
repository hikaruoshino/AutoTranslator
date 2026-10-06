# Verifies libs/json.lua number tokens stop at ']' (Lua 5.1 class []%s,%}[{]).
$ErrorActionPreference = 'Stop'
$jsonLua = Get-Content -Raw -Path (Join-Path $PSScriptRoot '..\libs\json.lua')
if ($jsonLua.IndexOf("str:find('[]%s,%}[{]'") -lt 0) {
    throw "json.lua is missing the number terminator class []%s,%}[{]"
}

function Get-LuaNumberEnd {
    param([string]$Str, [int]$Pos)
    $terminators = New-Object 'System.Collections.Generic.HashSet[char]'
    foreach ($ch in @(']', ',', '}', '[', '{', ' ', "`t", "`r", "`n")) {
        [void]$terminators.Add($ch)
    }
    for ($i = $Pos; $i -le $Str.Length; $i++) {
        if ($terminators.Contains($Str[$i - 1])) { return $i }
    }
    return $Str.Length + 1
}

function ConvertFrom-MiniJson {
    param([string]$Str)
    $script:pos = 1
    function Skip-Ws {
        while ($script:pos -le $Str.Length -and [char]::IsWhiteSpace($Str[$script:pos - 1])) {
            $script:pos++
        }
    }
    function Parse-Str {
        $start0 = $script:pos - 1
        $searchFrom = $start0 + 1
        while ($true) {
            $idx = $Str.IndexOf('"', $searchFrom)
            if ($idx -lt 0) { return '' }
            if ($idx -eq 0 -or $Str[$idx - 1] -ne [char]0x5C) { break }
            $searchFrom = $idx + 1
        }
        $s = $Str.Substring($script:pos, $idx - $script:pos)
        $script:pos = $idx + 2
        return $s
    }
    function Parse-Val {
        Skip-Ws
        if ($script:pos -gt $Str.Length) { return $null }
        $c = $Str[$script:pos - 1]
        if ($c -eq '"') { return Parse-Str }
        if ($c -eq '{') {
            $script:pos++
            $obj = @{}
            Skip-Ws
            if ($script:pos -le $Str.Length -and $Str[$script:pos - 1] -eq '}') { $script:pos++; return $obj }
            while ($script:pos -le $Str.Length) {
                Skip-Ws
                $k = Parse-Str
                Skip-Ws
                if ($script:pos -le $Str.Length -and $Str[$script:pos - 1] -eq ':') { $script:pos++ }
                $obj[$k] = Parse-Val
                Skip-Ws
                if ($script:pos -gt $Str.Length) { return $obj }
                $nc = $Str[$script:pos - 1]
                if ($nc -eq '}') { $script:pos++; return $obj }
                if ($nc -eq ',') { $script:pos++ }
            }
            return $obj
        }
        if ($c -eq '[') {
            $script:pos++
            $arr = New-Object System.Collections.ArrayList
            Skip-Ws
            if ($script:pos -le $Str.Length -and $Str[$script:pos - 1] -eq ']') { $script:pos++; return $arr }
            while ($script:pos -le $Str.Length) {
                [void]$arr.Add((Parse-Val))
                Skip-Ws
                if ($script:pos -gt $Str.Length) { return $arr }
                $nc = $Str[$script:pos - 1]
                if ($nc -eq ']') { $script:pos++; return $arr }
                if ($nc -eq ',') { $script:pos++ }
            }
            return $arr
        }
        $e = Get-LuaNumberEnd -Str $Str -Pos $script:pos
        $token = $Str.Substring($script:pos - 1, $e - $script:pos)
        $script:pos = $e
        if ($token -eq 'true') { return $true }
        if ($token -eq 'false') { return $false }
        if ($token -eq 'null') { return $null }
        return [double]$token
    }
    return Parse-Val
}

function Assert-Equal($actual, $expected, $label) {
    if ($actual -ne $expected) {
        throw "FAIL $label : expected=$expected actual=$actual"
    }
    Write-Host "ok $label"
}

$str = '[1,2,3]'
$posLast = 6

$oldEnd = $null
for ($i = $posLast; $i -le $str.Length; $i++) {
    $ch = $str[$i - 1]
    if ($ch -eq ',' -or $ch -eq '}' -or [char]::IsWhiteSpace($ch)) { $oldEnd = $i; break }
}
if ($null -ne $oldEnd) { throw 'old terminator unexpectedly matched ]' }
$oldToken = $str.Substring($posLast - 1)
Assert-Equal $oldToken '3]' 'repro: last token was 3]'
$parsedOld = 0
if ([double]::TryParse($oldToken, [ref]$parsedOld)) {
    throw 'tonumber(3]) should fail'
}

$newEnd = Get-LuaNumberEnd -Str $str -Pos $posLast
$newToken = $str.Substring($posLast - 1, $newEnd - $posLast)
Assert-Equal $newToken '3' 'fix: last token is 3'

$decoded = ConvertFrom-MiniJson -Str '[1,2,3]'
Assert-Equal $decoded.Count 3 'array length'
Assert-Equal ([int]$decoded[0]) 1 'arr[1]'
Assert-Equal ([int]$decoded[1]) 2 'arr[2]'
Assert-Equal ([int]$decoded[2]) 3 'arr[3]'

$obj = ConvertFrom-MiniJson -Str '{"n":10}'
Assert-Equal ([int]$obj['n']) 10 'object number still works'

$nested = ConvertFrom-MiniJson -Str '{"choices":[{"index":0}]}'
Assert-Equal ([int]$nested['choices'][0]['index']) 0 'nested index before }'

Write-Host 'All json decode checks passed.'
