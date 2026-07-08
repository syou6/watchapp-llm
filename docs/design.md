# 声に反応する Apple Watch アプリ — 設計メモ

リアルタイムで声を拾い、それについて解説やツッコミ（リアクション）を返すアプリの構成案。
「ローカル・高速・プライベート」を優先。

---

## 全体方針

- **Watch は「集音＋薄いクライアント」に徹する。重い LLM は iPhone で回す。**
  Apple Watch は最新モデルでも RAM が約 1GB しかなく、実用的な LLM（3B〜）は載らない。
- 処理は自分の端末内で完結 → オフライン可・データが外に出ない。
- 反応は **短く・ストリーミング**で返して体感速度を稼ぐ。
- 前提: 生成中は **iPhone が近くにある（reachable）**こと。これを外したいなら watchOS 27 の Private Cloud Compute 版（後述）。

---

## アーキテクチャ（3 層）

### 1. Apple Watch アプリ（capture + client）

役割:
- マイク集音（AVAudioEngine）
- VAD（音声区間検出）で発話を切り出す
- 発話音声（圧縮）を iPhone へ送る ← **STT は iPhone 側の方が確実**
- iPhone から返る解説テキストを表示（＋任意で `AVSpeechSynthesizer` で読み上げ）

注意点:
- watchOS は **常時バックグラウンド集音が制限**される。前面表示中か、ワークアウト的なアクティブセッションでマイクを維持するのが現実的。「一日中聞きっぱなし」は電池・OS ポリシー的に厳しい。
- 「短時間オン」設計にして電池を守る。

### 2. 通信（WatchConnectivity / WCSession）

- reachable な時は `sendMessage(Data:)` でリアルタイム、非 reachable 時は `transferFile` / `transferUserInfo` にフォールバック。
- 音声はチャンクで送信。返答テキストは逐次受信して即表示。

### 3. iPhone アプリ（頭脳）

- **STT**: WhisperKit（on-device Whisper、ストリーミング＋VAD、日本語対応）。
  もっと軽くしたいなら Apple 純正 `SFSpeechRecognizer`（on-device 日本語）でも可。
- **LLM（2 択）**:
  - *手軽ルート*: Apple **Foundation Models**（iOS 26、端末内 約3B、無料、guided generation、ストリーミング）。短い反応向き。※ Apple Intelligence 対応端末（iPhone 15 Pro 以降クラス）が必要。
  - *自由度ルート*: **MLX**（`mlx-swift-lm` / `mlx-swift-examples`）または **LocalLLMClient**。モデルは日本語が強い Qwen3-4B-Instruct-4bit など。対応端末の幅が広い。
- **生成**: system プロンプトで「解説役／ツッコミ役」の人格を定義 → transcript を渡す → トークンを逐次 Watch へ送る。
- 任意: **SpeakerKit** で話者分離（誰の発言か区別したい場合）。

---

## 使える主要リポジトリ

### 音声（STT / TTS / 話者分離）
- **argmaxinc/WhisperKit** — on-device Whisper。iOS/watchOS 対応、ストリーミング＋VAD、MIT ライセンス。同じ Swift パッケージ内に **TTSKit**（日本語音声あり）と **SpeakerKit**（話者分離）も同梱。
  https://github.com/argmaxinc/WhisperKit

### 端末内 LLM
- **ml-explore/mlx-swift** — MLX の Swift API 本体。
  https://github.com/ml-explore/mlx-swift
- **ml-explore/mlx-swift-examples** — `MLXChatExample` / `LLMEval` など iOS+macOS で動く実例。ここから始めるのが早い。
  https://github.com/ml-explore/mlx-swift-examples
- **ml-explore/mlx-swift-lm** — LLM/VLM 実装＋`ChatSession` API。Qwen・Gemma など多数対応。
  https://github.com/ml-explore/mlx-swift-lm
- **tattn/LocalLLMClient** — MLX と llama.cpp と FoundationModels を一本化した Swift パッケージ。iPhone で Qwen 系が動く実績あり。バックエンドを差し替えやすい。
  https://github.com/tattn/LocalLLMClient
- **preternatural-explore/mlx-swift-chat** — MLX のネイティブ SwiftUI チャット UI 参考。
  https://github.com/preternatural-explore/mlx-swift-chat

### Watch 音声アシスタントの参考（※バックエンドをローカルに差し替える前提）
- **jacobamobin/AppleIntelligenceWatchOS** — 声で話しかけて音声で返す watchOS 実装（元はクラウド API）。UI・フローの参考に。
  https://github.com/jacobamobin/AppleInteligenceWatchOS

### モデル配布
- **Hugging Face: mlx-community** — Qwen3-4B-Instruct-4bit、Gemma3-4B、Llama 3.2 などの MLX 変換済みモデル。
  https://huggingface.co/mlx-community

---

## データフロー（1 発話ぶん）

1. **Watch**: 集音 → VAD で区間確定（話者が止まって ~0.3 秒）
2. **Watch → iPhone**: 音声チャンク送信
3. **iPhone**: WhisperKit で文字起こし（ストリーミング）
4. **iPhone**: LLM に transcript＋system プロンプト → トークン生成開始（Foundation Models なら初トークンほぼ即時）
5. **iPhone → Watch**: テキストを逐次送信 → 表示（＋任意で読み上げ）

体感: 相手が話し終えて **~1〜2 秒**で短い反応が出る想定。
速さの肝は「反応を短く保つ」＋「ストリーミング」＋「iPhone が近い」。

---

## つくる順番（MVP → 拡張）

1. **iPhone 単体**で「音声 → STT → LLM → テキスト」を先に完成させる（Watch は後回し）。ここが心臓。
2. まず **Foundation Models** で最短で動かして、反応の質を確認。
3. **WhisperKit ＋ MLX（Qwen）**に差し替えて、日本語と自由度を上げる。
4. **WatchConnectivity** で Watch 集音クライアントを接続。
5. VAD・区間送信を最適化。必要なら TTS／話者分離を追加。
6. （2026 秋〜）watchOS 27 なら **Private Cloud Compute 直呼び**で iPhone 依存を外す選択肢も検討。

---

## モデル選びの目安

| 目的 | おすすめ |
|---|---|
| 日本語の質重視・端末内 | Qwen3-4B-Instruct-4bit / Gemma3-4B |
| とにかく手軽・無料 | Foundation Models（約3B） |
| iPhone でより大きいモデル | Increased Memory Limit entitlement を付与して 4bit 量子化モデル |

---

## 判断メモ（なぜこの形か）

- **Watch で LLM を回さない**理由: RAM 約 1GB。載る極小モデルでは「気の利いた解説」は無理。
- **STT を iPhone 側**に置く理由: Watch 単体 STT は非力＆電池食い。音声チャンクを送って iPhone で処理する方が安定。どうしても Watch 側で軽く返したい短文だけ `SFSpeechRecognizer` を併用する手もある。
- **Foundation Models と MLX の使い分け**: 立ち上げは Foundation Models が最速（3 行で呼べる）。日本語の言い回しやキャラ付けを詰めるなら MLX で Qwen に載せ替え。
