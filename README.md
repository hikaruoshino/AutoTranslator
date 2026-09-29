# AutoTranslator - FF11 Windower 4 Addon

[日本語] / [English]

---

## Overview / プロジェクト概要

**AutoTranslator** は、ファイナルファンタジーXI（FF11）の Windower 4 環境で動作するリアルタイム双方向チャット翻訳アドオンです。Windowerの `incoming text` イベントエンジンを通じてゲーム内チャット（内部の `0x017 Incoming Chat` パケット等）を常時キャプチャし、外部のAI翻訳APIと連携してログを瞬時に指定言語へ翻訳します。翻訳結果は Windower 標準の `libs/texts` ライブラリ（`texts.new`, `texts.pos`, `texts.color`, `texts.bg_alpha` 等）を用いて画面上のHUDオーバーレイに表示されるため、文字サイズや背景透過度、ドラッグ＆ドロップによる表示位置の調整（`draggable`）自在に行えます。

**AutoTranslator** is a real-time bidirectional chat translation addon for Final Fantasy XI (FF11) running on the Windower 4 environment. It captures in-game chat logs via Windower's `incoming text` event engine (which processes raw `0x017 Incoming Chat` packets under the hood) and seamlessly translates messages into your designated language using external AI translation APIs. Translated text is rendered directly on screen via Windower's standard `libs/texts` library (`texts.new`, `texts.pos`, `texts.color`, `texts.bg_alpha`, etc.), providing a customizable HUD overlay with adjustable font size, background opacity, and drag-and-drop repositioning (`draggable`).

---

## Features / 主な機能

- **日英/英日双方向翻訳 / Japanese-English Bidirectional Translation**
  - 簡単なコマンドで即座に翻訳先言語を切り替え可能（`//at lang ja/en`）。
  - Easily switch output translation language on the fly (`//at lang ja/en`).

- **マルチプロバイダー対応 / Multi-Provider Support**
  - OpenAI (`gpt-4o-mini`), Anthropic (`Claude 3 Haiku`), および `DeepL` の各種APIに対応。
  - Supports multiple translation services including OpenAI (`gpt-4o-mini`), Anthropic (`Claude 3 Haiku`), and `DeepL` APIs.

- **定型文辞書（【 】）保護 / FFXI Auto-Translate Tag Handling**
  - FF11固有の定型文辞書タグ（`【 】` または `0xFD` バイトマーカー）を解析し、APIリクエスト時に破損させず保持・適切に変換。
  - Safely detects and preserves native FFXI Auto-Translate dictionary tags (`【 】` / `0xFD` byte markers) during API calls to prevent translation distortion.

- **オンスクリーンHUD表示 / On-Screen HUD Overlay**
  - Windowerの `libs/texts` を利用した軽量オーバーレイ表示。フォントサイズ、カラー、背景透過度の変更、ドラッグ＆ドロップ移動に対応。
  - Lightweight overlay powered by Windower's `libs/texts` library, supporting custom font sizes, text/background colors, opacity, and drag-and-drop positioning.

- **チャットフィルター & プレイヤーブロック / Chat Filter & Player Blocklist**
  - Say, Party, Tell などのチャット種別ごとの翻訳ON/OFF設定や、特定プレイヤーの発言を翻訳除外するブロック機能。
  - Filter translations by specific chat channels (Say, Party, Tell, etc.) or ignore messages from blocked players.

- **NGワード検知 / NG Word Suppression**
  - 登録した不適切な単語やスラングを含む発言の翻訳を遮蔽・スキップ。
  - Skip or block translation of messages containing specific registered words or toxic phrases.

- **低遅延設計 / Low-Latency Pipeline**
  - ログ受信処理および外部API呼び出しの最適化により、パーティプレイ中もスムーズな表示を実現。
  - Optimized log processing and API request pipelines ensure minimal delay during intensive gameplay.

---

## Installation / インストール方法

1. Windower 4 の `addons` フォルダを開きます。（例: `C:\Windower4\addons\`）
   Open your Windower 4 `addons` directory. (Example: `C:\Windower4\addons\`)

2. `addons` フォルダ内に `AutoTranslator` という名称のフォルダを作成します。（パス: `Windower4\addons\AutoTranslator\`）
   Create a new folder named `AutoTranslator` inside `addons`. (Path: `Windower4\addons\AutoTranslator\`)

3. 本リポジトリからダウンロードしたファイル群（`AutoTranslator.lua`, `filler.xml.example` 等）を上記フォルダへ配置します。
   Download and place all repository files (`AutoTranslator.lua`, `filler.xml.example`, etc.) into that folder.

4. `filler.xml.example` を複製（またはリネーム）し、ファイル名を `filler.xml` に変更します。
   Duplicate (or rename) `filler.xml.example` and set its name to `filler.xml`.

---

## Configuration / 設定方法

`filler.xml` をテキストエディタで開き、取得した各種サービスのAPIキー、使用モデル、およびシステムプロンプトを設定します。ネットスラング（`w`, `草`, `tbh`, `smh` 等）やFF11固有の略称・呪文名を自然に翻訳するため、`<system_prompt>` セクションでAIモデルへのコンテキスト指示を柔軟にカスタマイズ可能です。

Open `filler.xml` in a text editor and enter your API keys, chosen models, and system prompts. To ensure accurate handling of gaming jargon (`w`, `草`, `tbh`, `smh`), localized spell names, and informal chat tone, you can customize context instructions in the `<system_prompt>` section.

### 設定ファイル構造例 / XML Configuration Example

```xml
<?xml version="1.0" ?>
<settings>
    <global>
        <!-- 翻訳エンジン選択: openai / claude / deepl -->
        <provider>openai</provider>
        
        <!-- 使用モデル指定 / Model Selection -->
        <openai_model>gpt-4o-mini</openai_model>
        <claude_model>claude-3-haiku-20240307</claude_model>

        <!-- 翻訳先言語: ja (日本語) / en (英語) -->
        <language>ja</language>
        
        <!-- API Keys -->
        <openai_api_key>YOUR_OPENAI_API_KEY_HERE</openai_api_key>
        <claude_api_key>YOUR_CLAUDE_API_KEY_HERE</claude_api_key>
        <deepl_api_key>YOUR_DEEPL_API_KEY_HERE</deepl_api_key>
        
        <!-- 翻訳対象モード: chat / party / tell / all -->
        <mode>all</mode>

        <!-- LLM用システム指示文（ゲームスラング・定型文補正指示） -->
        <system_prompt>You are an expert FFXI game chat translator. Translate informal online gaming chat between English and Japanese. Preserve gamer slang (e.g., 'w', '草', 'tbh', 'smh'), keep localized FFXI spell/item names accurate, preserve FFXI auto-translate brackets 【 】, and maintain a natural, concise chat tone.</system_prompt>
    </global>
</settings>
```

> **注意 / Note:** 
> `filler.xml` には実際のAPIキーが含まれるため、絶対にGitHub等の公開リポジトリにアップロードしないでください。
> Never upload your actual `filler.xml` to public repositories as it contains sensitive API keys.

---

## Usage & Command Reference / 使い方・コマンド一覧

ゲーム内のチャットラインまたはWindowerコンソールから以下のコマンドを実行できます。

You can execute the following commands via the in-game chat bar or the Windower console.

| コマンド / Command | 説明 / Description | 使用例 / Example |
| :--- | :--- | :--- |
| `//at lang <ja\|en>` | 翻訳出力言語を切り替えます。<br>Switches target translation language. | `//at lang en` |
| `//at provider <openai\|claude\|deepl>` | 翻訳エンジン（APIプロバイダー）を切り替えます。<br>Changes the active API provider. | `//at provider deepl` |
| `//at mode <chat\|party\|tell\|all>` | 翻訳対象のチャット範囲を変更します。<br>Changes the chat filtering scope. | `//at mode party` |
| `//at block <add\|del\|list> <player>` | 特定プレイヤーの翻訳ブロック管理を行ないます。<br>Manages player blocklist for translation. | `//at block add ShadowLord` |
| `//at word <add\|del\|list> <word>` | NGワード（翻訳スキップ対象）の管理を行ないます。<br>Manages NG word filter list. | `//at word add spamword` |

---

## Troubleshooting / トラブルシューティング

**Q. APIキーエラーが発生して翻訳されません。 / API Key Error occurs and messages are not translated.**
* `filler.xml` 内のAPIキー文字列が正しく設定されているか確認してください。余分なスペースや改行が含まれていると認証に失敗する場合があります。
* Ensure that your API keys are correctly entered in `filler.xml` without extra spaces or line breaks.

**Q. 特定のチャット（PartyやTell）が翻訳されません。 / Certain chat channels (Party or Tell) are not being translated.**
* `//at mode all` を実行して、フィルター設定がすべてのチャットを対象にしているか確認してください。また、対象プレイヤーがブロックリストに入っていないか `//at block list` で確認してください。
* Execute `//at mode all` to clear restricted chat filters. Also check `//at block list` to confirm the sender is not accidentally blocked.

**Q. 翻訳が表示されるまでに時間がかかります（遅延発生）。 / High latency or delays in receiving translation outputs.**
* 利用中のAPIプロバイダーの障害や混雑状態を確認するか、`//at provider` コマンドで別のプロバイダー（例: `gpt-4o-mini` や `DeepL`）へ切り替えて改善するか試してください。
* Check the status of your chosen service provider or try switching to another provider using `//at provider <provider_name>`.

**Q. ゲーム内の定型文（【 】）が文字化けしたり翻訳エラーになります。 / FFXI Auto-Translate tags (【 】) are garbled or failing.**
* 定型文タグ内に特殊文字が含まれている場合、`<system_prompt>` 内の指示で `【 】` を保持するルールが記述されているか確認してください。
* Verify that your `<system_prompt>` in `filler.xml` explicitly instructs the AI model to preserve `【 】` tags without altering internal byte markers.

---

## License & Disclaimer / ライセンス・免責事項

### Open Source License
This project is released under the BSD 3-Clause License, adhering to standard Windower addon development guidelines.

```text
Copyright © 2026, AutoTranslator Developers / Windower
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

* Neither the name of Windower nor the names of its contributors may be used
  to endorse or promote products derived from this software without specific
  prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### Disclaimer / 免責事項

**日本語:**
本ツールは有志によって開発されたサードパーティ製のオープンソースアドオンであり、株式会社スクウェア・エニックス（SQUARE ENIX CO., LTD.）とは一切関係ありません。本ツールの使用によって生じたゲームアカウントへの不利益、データ消失、その他の損害について、開発者および権利者は一切の責任を負いません。すべて自己責任においてご使用ください。

**English:**
This tool is an unofficial third-party open-source addon developed by volunteers and is not affiliated with or endorsed by Square Enix Co., Ltd. The developers and contributors assume no responsibility or liability for any account penalties, data loss, or other damages arising from the use of this software. Use this software entirely at your own risk.
