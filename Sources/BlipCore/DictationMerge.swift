/// How spoken words join what was already in the text box when the mic was pressed.
public enum DictationMerge {
  /// `prefix` followed by `dictated`, with one space between them when both are non-empty and
  /// `prefix` does not already end in whitespace. Each new partial result is merged with the
  /// same `prefix`, so it replaces the dictated part rather than adding to it.
  public static func text(prefix: String, dictated: String) -> String {
    guard !prefix.isEmpty, !dictated.isEmpty else { return prefix + dictated }
    let separator = prefix.last!.isWhitespace ? "" : " "
    return prefix + separator + dictated
  }
}
