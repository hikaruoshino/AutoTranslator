# Azure 用の JSON の組み立てと、応答の読み取りの確認 (ネットワークは使わない)
# 実行: powershell -NoProfile -File tests\azure_json_test.ps1
$ErrorActionPreference = 'Stop'
$fails = 0
function Check([bool]$cond, [string]$msg) { if (-not $cond) { $script:fails++; Write-Output ('NG: ' + $msg) } }

# 1. 送る JSON: 要素が 1 つでも配列になる。引用符・円記号・日本語・< > & が壊れない
$text = 'lets go to "Norg" \ / <b> & ' + [char]0x30CE + [char]0x30FC + [char]0x30B0
$json = '[{"Text":' + ($text | ConvertTo-Json -Compress) + '}]'
Check ($json.StartsWith('[{"Text":"') -and $json.EndsWith('"}]')) '配列の形で始まり終わる'
$back = $json | ConvertFrom-Json
Check ($back.Count -eq 1) '要素が 1 つ'
Check ([string]$back[0].Text -eq $text) '元の文に戻る (記号・日本語)'

# 2. 応答の読み取り (Azure の v3.0 の形)
$res = '[{"detectedLanguage":{"language":"en","score":1.0},"translations":[{"text":"ABC","to":"ja"}]}]' | ConvertFrom-Json
Check ([string]$res[0].translations[0].text -eq 'ABC') '応答から訳文を取れる'

# 3. Invoke-Azure の形が、ソースにあること (関数の定義と、Invoke-Provider の azure の分岐)
$src = [IO.File]::ReadAllText((Join-Path (Split-Path $PSScriptRoot -Parent) 'helper\at_helper.ps1'), [Text.Encoding]::UTF8)
Check ($src.Contains('function Invoke-Azure')) 'Invoke-Azure がある'
Check ($src.Contains("'azure' {")) 'Invoke-Provider に azure の分岐がある'
Check ($src.Contains("Ocp-Apim-Subscription-Key")) 'キーのヘッダーがある'

# 4. 辞書の指定 (ヘルパーの「azure-dictionary」の区間だけを取り出して動かす)
$m = [regex]::Match($src, '# --- azure-dictionary:begin ---(.*?)# --- azure-dictionary:end ---', 'Singleline')
Check $m.Success '辞書の指定の区間が見つかる'
$tmpTsv = Join-Path ([IO.Path]::GetTempPath()) ('at_gloss_test_' + [Guid]::NewGuid().ToString('N') + '.tsv')
$norg = 'Norg' + "`t" + [char]0x30CE + [char]0x30FC + [char]0x30B0
$ng = 'North Gustaberg' + "`t" + [char]0x5317 + 'G'
$gus = 'Gustaberg' + "`t" + 'G'
[IO.File]::WriteAllLines($tmpTsv, @($norg, $gus, $ng), (New-Object Text.UTF8Encoding($false)))
try {
    $GlossaryPairs = @{ 'en-ja' = @{ Tsv = $tmpTsv } }
    function Write-Log([string]$msg) {}
    Invoke-Expression $m.Groups[1].Value
    $entries = Get-AzureGlossary
    Check ($entries.Count -eq 3) '用語集を 3 件読む'
    Check ($entries[0].En -eq 'North Gustaberg') '長い名前が先に並ぶ'
    $h = ConvertTo-AzureHtml 'lets go to Norg & NORG, then North Gustaberg <now>' $entries
    Check ($h.Count -eq 3) ('3 か所を囲む (実際 ' + $h.Count + ')')
    Check ($h.Html.Contains('<mstrans:dictionary translation="' + [char]0x30CE + [char]0x30FC + [char]0x30B0 + '">Norg</mstrans:dictionary>')) 'Norg を囲む'
    Check ($h.Html.Contains('>NORG</mstrans:dictionary>')) '大文字小文字を区別せず、元の綴りを残す'
    Check ($h.Html.Contains('>North Gustaberg</mstrans:dictionary>') -and -not $h.Html.Contains('>Gustaberg</mstrans:dictionary>')) '長い名前を優先し、重ねて囲まない'
    Check ($h.Html.Contains('&amp;') -and $h.Html.Contains('&lt;now&gt;')) '記号を HTML にする'
    $h2 = ConvertTo-AzureHtml 'Norgs and xNorg and Norgx' $entries
    Check ($h2.Count -eq 0) '別の語の一部は囲まない'
    # 応答の後始末 (印を外し、文字参照を戻す)
    $resp = [regex]::Replace('A &amp; B <mstrans:dictionary translation="x">y</mstrans:dictionary>', '<[^>]+>', '')
    Check ([System.Net.WebUtility]::HtmlDecode($resp) -eq 'A & B y') '応答の印を外して文字参照を戻す'
} finally {
    Remove-Item -LiteralPath $tmpTsv -Force -ErrorAction SilentlyContinue
}

if ($fails -eq 0) { Write-Output 'OK azure_json_test: 失敗 0 件' } else { Write-Output ('FAILED ' + $fails); exit 1 }
