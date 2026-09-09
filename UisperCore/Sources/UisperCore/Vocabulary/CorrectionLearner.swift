import Foundation

/// Works out which words the user corrected by hand after dictation, so they can be added to
/// the vocabulary and spelled right next time.
public enum CorrectionLearner {
    /// A correction has to look like a mishearing, not an unrelated word: "Shunade" → "Sinead"
    /// is 4 edits over 7 characters (0.57) and counts, a swapped word does not.
    static let maxEditRatio = 0.65
    /// Below this, a "correction" is more likely a typo fix or an article than a name.
    static let minWordLength = 3
    /// How many words worse than the best match a later copy may be and still win. An edited
    /// copy differs from the original by the words the user changed, which is very few.
    static let editedRegionSlack = 3
    /// The corrected words to add to the vocabulary, or empty when the edits are not corrections.
    /// - Parameters:
    ///   - originalText: what dictation inserted.
    ///   - fieldValue: what the field holds now, after the user's edits.
    ///   - existingDictionary: words already known, so they are not offered twice.
    public static func extractCorrections(originalText: String, fieldValue: String,
                                          existingDictionary: [String]) -> [String] {
        guard !originalText.isEmpty, !fieldValue.isEmpty, originalText != fieldValue else { return [] }

        let editedRegion = editedRegion(originalText: originalText, fieldValue: fieldValue)
        guard editedRegion != originalText else { return [] }

        let originalWords = tokenize(originalText)
        let editedWords = tokenize(editedRegion)
        guard !originalWords.isEmpty, !editedWords.isEmpty else { return [] }

        let substitutions = substitutions(from: originalWords, to: editedWords)

        let known = Set(existingDictionary.map { $0.lowercased() })
        var seen = Set<String>()
        var out: [String] = []
        for (original, corrected) in substitutions {
            let key = corrected.lowercased()
            guard !known.contains(key), seen.insert(key).inserted,
                  original.lowercased() != key, corrected.count >= minWordLength,
                  isNameShaped(corrected), !Self.isSuffixEdit(original, corrected) else { continue }
            let distance = editDistance(original.lowercased(), key)
            let longest = max(original.count, corrected.count)
            guard longest > 0, Double(distance) / Double(longest) <= maxEditRatio else { continue }
            out.append(corrected)
        }
        return out
    }

    /// A vocabulary entry has to be a word, not a stray token off the screen.
    ///
    /// `tokenize` only trims punctuation at the *edges*, so a token may still carry `:`, quotes
    /// or zero-width characters from whatever app the text came from, and every entry is
    /// interpolated into the cleanup prompt as a name to spell exactly.
    ///
    /// Case is deliberately not required: the names worth learning are often all-lowercase
    /// (`flykit`, `kubectl`, `tmux`). Ordinary edits are kept out by `isSuffixEdit` instead.
    static func isNameShaped(_ word: String) -> Bool {
        // Not `isWordCharacter`: that allows `_`, and `Kubernetes_ignore_all_prior` is one token
        // with no whitespace, so it survives tokenizing and lands in the prompt as a name.
        // `\u{2019}` is the curly apostrophe macOS substitutes by default, as in O’Brien.
        word.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "'" || $0 == "\u{2019}" || $0 == "-" })
            && word.contains(where: \.isLetter)
    }

    /// True when the edit only added or removed a short ending: "call" → "called", "test" →
    /// "tests", "deploy" → "deployed". Those are grammar fixes, not names, and learning them
    /// would fill the list and bias the speech engine toward ordinary words. A real mishearing
    /// differs in the middle ("flykid" → "flykit"), so it survives this.
    static func isSuffixEdit(_ a: String, _ b: String) -> Bool {
        let (short, long) = a.count <= b.count ? (a.lowercased(), b.lowercased()) : (b.lowercased(), a.lowercased())
        guard long.count - short.count <= 3 else { return false }
        return long.hasPrefix(short)
    }

    /// Words with punctuation trimmed off both ends. Keeps letters, digits and underscores.
    static func tokenize(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).compactMap { word in
            let trimmed = word.drop(while: { !isWordCharacter($0) })
                .reversed().drop(while: { !isWordCharacter($0) }).reversed()
            return trimmed.isEmpty ? nil : String(trimmed)
        }
    }

    private static func isWordCharacter(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }

    /// The part of `fieldValue` that corresponds to the dictated text. The field may hold much
    /// more than what dictation inserted, and only the inserted part may be compared.
    static func editedRegion(originalText: String, fieldValue: String) -> String {
        if Double(fieldValue.count) <= Double(originalText.count) * 1.5 { return fieldValue }
        // No "the text is still in there unchanged, so stop" shortcut: a terminal screen holds
        // both the sentence the user was asked to dictate and the one they typed, so the
        // untouched copy is always present and the shortcut would report no edit every time.
        // An unedited field costs one window scan and still finds no substitutions.

        let originalWords = tokenize(originalText)
        let fieldWords = tokenize(fieldValue)
        let window = originalWords.count
        guard fieldWords.count > window, window > 0 else { return fieldValue }

        var scores: [Int] = []
        for start in 0...(fieldWords.count - window) {
            var matches = 0
            for offset in 0..<window
            where fieldWords[start + offset].lowercased() == originalWords[offset].lowercased() {
                matches += 1
            }
            scores.append(matches)
        }
        guard let best = scores.max() else { return fieldValue }
        // Under 30% word overlap nothing here is the dictated text.
        guard Double(best) >= Double(window) * 0.3 else { return fieldValue }
        // The *last* near-perfect match, not the first best one. A screen often holds an earlier
        // copy of the same sentence — a terminal shows what was asked as well as what was typed,
        // and the untouched copy always scores higher than the edited one. Taking the best match
        // there compares the text with itself and finds no edit at all. The user's own copy is
        // the most recent, so recency decides between matches that are close.
        let acceptable = max(best - editedRegionSlack, Int((Double(window) * 0.3).rounded(.up)))
        let start = scores.lastIndex(where: { $0 >= acceptable }) ?? 0
        return fieldWords[start..<(start + window)].joined(separator: " ")
    }

    /// Word-level longest-common-subsequence alignment, reduced to `(original, corrected)` pairs.
    /// A substitution is one dropped original word immediately followed by one added edited word.
    static func substitutions(from originalWords: [String], to editedWords: [String]) -> [(String, String)] {
        let m = originalWords.count
        let n = editedWords.count
        guard m > 0, n > 0 else { return [] }
        var lcs = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                if originalWords[i - 1].lowercased() == editedWords[j - 1].lowercased() {
                    lcs[i][j] = lcs[i - 1][j - 1] + 1
                } else {
                    lcs[i][j] = max(lcs[i - 1][j], lcs[i][j - 1])
                }
            }
        }

        var aligned: [(String?, String?)] = []
        var i = m
        var j = n
        while i > 0 || j > 0 {
            if i > 0, j > 0, originalWords[i - 1].lowercased() == editedWords[j - 1].lowercased() {
                aligned.insert((originalWords[i - 1], editedWords[j - 1]), at: 0)
                i -= 1
                j -= 1
            } else if j > 0, i == 0 || lcs[i][j - 1] >= lcs[i - 1][j] {
                aligned.insert((nil, editedWords[j - 1]), at: 0)
                j -= 1
            } else {
                aligned.insert((originalWords[i - 1], nil), at: 0)
                i -= 1
            }
        }

        var out: [(String, String)] = []
        for k in aligned.indices.dropLast() {
            guard let dropped = aligned[k].0, aligned[k].1 == nil,
                  aligned[k + 1].0 == nil, let added = aligned[k + 1].1 else { continue }
            out.append((dropped, added))
        }
        return out
    }

    /// Levenshtein distance, on characters.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a)
        let b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        var current = previous
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                current[j] = a[i - 1] == b[j - 1]
                    ? previous[j - 1]
                    : 1 + min(previous[j], current[j - 1], previous[j - 1])
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
