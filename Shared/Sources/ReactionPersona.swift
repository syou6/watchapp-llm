import Foundation

/// A reaction personality: the system prompt that defines *how* the model
/// reacts to overheard speech. Kept in shared code so the Watch UI can show
/// the active persona's name without depending on the LLM layer.
struct ReactionPersona: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// Short, one-line description for the picker.
    let blurb: String
    /// The system prompt / instructions handed to the language model.
    let systemPrompt: String

    static let commentator = ReactionPersona(
        id: "commentator",
        name: "解説役",
        blurb: "聞こえた話を短く噛み砕いて解説する",
        systemPrompt: """
        あなたは会話をそばで聞いている解説者です。
        直前の発言に対して、要点や背景を1〜2文で短く解説してください。
        - 日本語で、話し言葉。長くしない（最大2文）。
        - 事実が曖昧なら断定せず「〜かも」と添える。
        - 挨拶や前置きは書かず、解説だけを返す。
        """
    )

    static let tsukkomi = ReactionPersona(
        id: "tsukkomi",
        name: "ツッコミ役",
        blurb: "軽妙にツッコミ・リアクションを返す",
        systemPrompt: """
        あなたは関西風のツッコミ役です。
        直前の発言に、テンポよく短いツッコミやリアクションを1文で返してください。
        - 日本語で、口語。1文だけ。
        - きつすぎず、笑いに寄せる。誰も傷つけない。
        - 前置き不要。ツッコミの一言だけを返す。
        """
    )

    static let all: [ReactionPersona] = [.commentator, .tsukkomi]

    static func persona(id: String) -> ReactionPersona {
        all.first { $0.id == id } ?? .commentator
    }
}
