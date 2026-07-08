# WatchVoiceLLM — 声に反応する Apple Watch アプリ

周囲の声をリアルタイムで拾い、**短い解説やツッコミ**をその場で返すアプリ。
[設計メモ](docs/design.md) の方針に沿った実装スケルトンです。

> **ローカル・高速・プライベート**：音声は端末内で処理され、外部には送信されません。

---

## 構成（3 層）

```
 Apple Watch  ──(音声チャンク)──▶   iPhone            ──(端末内)──▶  reaction
 集音 + VAD                        STT → LLM(streaming)
 薄いクライアント        ◀──(逐次テキスト)──          頭脳
```

- **Watch は集音に徹する**（RAM ~1GB では実用的な LLM は載らない）
- **STT と LLM は iPhone**：Watch から音声チャンクを送り、iPhone で処理
- 反応は **短く・ストリーミング**で返して体感速度を稼ぐ

STT と LLM はそれぞれ **プロトコルの裏**に置いてあり、利用可能なバックエンドを
優先度順に自動選択します（設計メモの「まず動かして、あとで質を上げる」ランプ）。

**STT — `SpeechTranscribing`**

| 実装 | 内容 | 優先 |
|---|---|---|
| `WhisperKitTranscriber` | WhisperKit（on-device Whisper・日本語） | パッケージがあれば優先 |
| `SystemSpeechTranscriber` | `SFSpeechRecognizer`（on-device 日本語・依存なし） | フォールバック |

**LLM — `ReactionGenerating`**

| 実装 | 内容 | 優先 |
|---|---|---|
| `MLXReactionEngine` | MLX + Qwen3-4B-4bit（自由度・日本語の質） | パッケージがあれば優先 |
| `FoundationModelsEngine` | Foundation Models（iOS 26・~3B・初トークン最速） | 次点 |
| `EchoReactionEngine` | モデル無しの擬似反応 | 最終フォールバック |

---

## ディレクトリ

```
Shared/Sources/          # 両ターゲット共通
  Messages.swift           WireMessage（Watch↔iPhone のワイヤ形式）
  AudioCodec.swift         PCM を Int16 にパック（軽量圧縮）
  VoiceActivityDetector.swift  エネルギーゲート VAD
  ReactionPersona.swift    解説役 / ツッコミ役の system プロンプト

iOS/Sources/             # iPhone（頭脳）
  Audio/                   AudioCapture（スタンドアロン検証用の自機マイク）
  Speech/                  SpeechTranscribing + SFSpeechRecognizer / WhisperKit + factory
  LLM/                     ReactionGenerating + MLX(Qwen) / FoundationModels / Echo + factory
  Pipeline/                ConversationPipeline（STT→LLM の心臓）
  Connectivity/            PhoneConnectivity（WCSession, チャンク再組立→pipeline）
  UI/                      ReactionView（スタンドアロン画面）

Watch/Sources/           # Apple Watch（薄いクライアント）
  Audio/                   WatchAudioCapture
  Connectivity/            WatchConnectivity（VAD→チャンク送信, 反応受信）
  UI/                      WatchReactionView
```

---

## ビルド手順（macOS + Xcode 必須）

Xcode プロジェクトは [XcodeGen](https://github.com/yonaskolb/XcodeGen) の
`project.yml` からテキストで生成します（差分がレビューしやすいため）。

```bash
brew install xcodegen
xcodegen generate          # → WatchVoiceLLM.xcodeproj
open WatchVoiceLLM.xcodeproj
```

1. `project.yml` の `DEVELOPMENT_TEAM` と bundle id を自分のものに変更
2. iPhone スキームを選んで実行（`EchoReactionEngine` によりモデル無しでも動作確認可）
3. 実機で **マイク / 音声認識** の許可を与える
4. Watch を接続すると、Watch のマイクから拾った声に iPhone が反応を返す

> Foundation Models は **iOS 26 + Apple Intelligence 対応端末**が必要です。
> 非対応環境では自動的に `EchoReactionEngine`（擬似反応）にフォールバックし、
> パイプライン全体を最後まで検証できます。

---

## つくる順番（設計メモ準拠）

- [x] 1. iPhone 単体で 音声 → STT → LLM → テキスト（`ConversationPipeline` + `ReactionView`）
- [x] 2. Foundation Models で最短起動（`FoundationModelsEngine`, フォールバック付き）
- [x] 3. WhisperKit + MLX(Qwen) に差し替え（`WhisperKitTranscriber` / `MLXReactionEngine` + ファクトリ自動選択）
- [x] 4. WatchConnectivity で Watch 集音クライアントを接続
- [x] 5. VAD・区間送信（`VoiceActivityDetector` + チャンク送信）
- [ ] 6. TTS（読み上げ）／話者分離（SpeakerKit）／watchOS 27 Private Cloud Compute

差し替えは各プロトコルの実装を足して `ReactionEngineFactory` / `ConversationPipeline`
の初期化を変えるだけ。呼び出し側（pipeline・UI）には手を入れません。

---

## 制約・注意

- watchOS は常時バックグラウンド集音が制限される。前面表示中を前提とした「短時間オン」設計。
  画面を消したまま拾い続けるには `HKWorkoutSession` でマイクを保持する必要があります。
- リアルタイム送受信は iPhone が reachable な前提。非 reachable 時は `transferUserInfo` に
  フォールバック（確定音声・最終テキストのみ）。
- 現状 `AudioCodec` は Int16 パックのみ。さらに絞るなら同ファイルで Opus/AAC に差し替え可能。
- **WhisperKit / MLX は重い**：`project.yml` の `packages` に登録済みで、初回ビルドで
  大きな Swift パッケージを解決し、モデル重み（Qwen3-4B-4bit ≈ 2.3GB）は初回実行時に
  ダウンロードされます。軽い Echo + `SFSpeechRecognizer` だけで動かしたい場合は、
  `project.yml` の該当 `packages` と `dependencies` をコメントアウトすれば
  `#if canImport(...)` により自動でフォールバックします。
- MLX の Metal 実行はシミュレータでは Apple Silicon Mac 上でのみ動作。実機推奨。

詳細な判断根拠は [設計メモ](docs/design.md) を参照。
