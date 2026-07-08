# インタラクティブ・プロトタイプ

`index.html` は、実機アプリの体験をブラウザで再現した UX プロトタイプです。
Mac がなくても「集音 → 文字起こし → 短い反応をストリーミング」の流れと速度感、
UI の質感を触って確認できます。

## 触る

任意のブラウザで `index.html` を開くだけ（ビルド不要・完全に自己完結）:

```bash
open prototype/index.html      # macOS
# または任意のブラウザにドラッグ&ドロップ
```

- Watch のマイクボタンをタップ → 日本語で話しかけると、背景のサウンドフィールドと
  Watch のリングが実際の声で波打ち、反応が Watch と iPhone に同時ストリーミング。
- マイク非対応/不許可のブラウザ（Firefox 等）でも、例文チップとテキスト入力から試せます。
- 解説役 / ツッコミ役を切り替え可能。

## 実機との対応

| 段階 | プロトタイプ | 実機アプリ |
|---|---|---|
| STT | Web Speech API（`ja-JP`） | `WhisperKit` / `SFSpeechRecognizer` |
| 反応 | `EchoReactionEngine` と同じ発想のローカル生成 | 端末内 LLM（`MLX + Qwen3-4B` / `Foundation Models`） |
| 表示 | Watch＋iPhone のストリーミング | 同左（`WatchConnectivity` 経由） |

あくまで**体験の流れと質感**を確認するためのもので、反応の質は実機の LLM で置き換わります。
