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
bootstrap.sh             # xcodegen 導入 → 生成 → Xcode を開く（実機セットアップ）
project.yml              # XcodeGen スペック（3ターゲット定義）

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

## 実機で試す（macOS + Xcode 必須）

Xcode プロジェクトは [XcodeGen](https://github.com/yonaskolb/XcodeGen) の
`project.yml` からテキストで生成します。クローン直後は**ワンコマンド**でOK:

```bash
./bootstrap.sh          # xcodegen を入れて生成し、Xcode を開く
```

> bundle id が無料プロビジョニングで弾かれる場合は自分のプレフィックスで:
> `BUNDLE_PREFIX=com.yourname.watchvoicellm ./bootstrap.sh`

Xcode が開いたら:

1. スキーム **WatchVoiceLLM** と実行先に**自分の iPhone** を選ぶ
2. 各ターゲット（`WatchVoiceLLM` と `WatchVoiceLLM-Watch`）の
   **Signing & Capabilities → Team** に自分を設定（無料 Apple ID 可・7日間有効）
3. **⌘R** でビルド＆実行 → 初回は **マイク / 音声認識** を許可
   - 初回、iPhone 側で *設定 > 一般 > VPN とデバイス管理* から開発者プロファイルを信頼
4. Apple Watch でも動かすには、iPhone アプリ導入後に **Watch スキーム**（実行先＝ペア
   済み Watch）を選んで実行

**初回のバックエンド（デフォルト = 高速パス）**
重い WhisperKit / MLX は既定で **OFF**。`SFSpeechRecognizer`（端末内・日本語）＋
Foundation Models（対応端末のみ、非対応は Echo に自動フォールバック）で、
**どの iPhone でも数秒でビルド**して反応ループを確認できます。

より自然な反応にしたくなったら、`project.yml` の
`WhisperKit` / `mlx-swift-lm` パッケージ2ブロック（`dependencies` と `packages`）を
アンコメントして `./bootstrap.sh` を再実行。コードは `#if canImport(...)` で
自動的に WhisperKit + MLX/Qwen に切り替わります（初回は大きな SPM 解決＋
モデル重み ≈2.3GB の DL。実機推奨）。

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
- **WhisperKit / MLX は既定で OFF**：初回ビルドを速くするため `project.yml` で
  コメントアウト済み。アンコメントで有効化すると、初回ビルドで大きな Swift パッケージを
  解決し、モデル重み（Qwen3-4B-4bit ≈ 2.3GB）は初回実行時にダウンロードされます。
  切り替えはコードに触れず `#if canImport(...)` が自動でフォールバック/昇格します。
- MLX の Metal 実行はシミュレータでは Apple Silicon Mac 上でのみ動作。実機推奨。

詳細な判断根拠は [設計メモ](docs/design.md) を参照。
