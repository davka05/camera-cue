import Foundation

struct ScriptFollower {
    let lines: [String]
    private(set) var index = 0
    private(set) var progress = 0.0

    private let normalizedLines: [[Character]]
    private var carriedSpeech: [Character] = []
    private var latestSpeech: [Character] = []
    private var consumedPrefix: [Character] = []

    init(lines: [String]) {
        self.lines = lines
        normalizedLines = lines.map(Self.normalize)
    }

    mutating func move(by offset: Int) {
        guard !lines.isEmpty else { return }
        let (destination, overflow) = index.addingReportingOverflow(offset)
        let boundedIndex = overflow ? lines.count - 1 : min(max(destination, 0), lines.count - 1)
        guard boundedIndex != index else { return }
        index = boundedIndex
        progress = 0
        // A later partial result will still contain words spoken before the manual move.
        consumedPrefix = latestSpeech
    }

    /// The recognizer supplies a cumulative transcript until it marks the task final.
    @discardableResult
    mutating func accept(_ phrase: String, isFinal: Bool) -> Bool {
        let update = Self.normalize(phrase)
        guard !update.isEmpty else {
            if isFinal {
                carriedSpeech = []
                latestSpeech = []
                consumedPrefix = []
            }
            return false
        }
        let speech = carriedSpeech + update
        latestSpeech = speech
        var start = max(consumedBoundary(in: speech), speech.count - 320)
        let initialIndex = index

        while index + 1 < lines.count {
            let available = speech[start...]
            if let end = Self.completion(of: normalizedLines[index], in: available) {
                index += 1
                start = end
            } else if let anchor = nextAnchor(in: available) {
                index = anchor.index
                start = anchor.start
            } else {
                break
            }
        }

        if index != initialIndex { progress = 0 }
        if normalizedLines.indices.contains(index), !normalizedLines[index].isEmpty, progress < 1 {
            let line = normalizedLines[index]
            let available = speech[start...]
            let isLastCue = index == lines.count - 1
            if isLastCue, Self.completion(of: line, in: available) != nil {
                progress = 1
            } else {
                let matched = Self.matchedPrefixLength(of: line, in: available)
                progress = max(progress, Double(matched) / Double(line.count))
            }
        }

        if isFinal {
            // Preserve an unfinished phrase if the speech engine starts a new task mid-line.
            carriedSpeech = Array(speech[start...].suffix(96))
            latestSpeech = carriedSpeech
            consumedPrefix = []
        } else if index != initialIndex {
            consumedPrefix = Array(speech[..<start])
        }
        return index != initialIndex
    }

    private func consumedBoundary(in speech: [Character]) -> Int {
        let boundary = consumedPrefix.count
        if boundary == 0 || speech.starts(with: consumedPrefix) { return boundary }

        // Recover the boundary if the recognizer revised words before it.
        let anchor = Array(consumedPrefix.suffix(12))
        if anchor.count >= 6 {
            let firstEnd = max(anchor.count, boundary - 20)
            let lastEnd = min(speech.count, boundary + 20)
            if firstEnd <= lastEnd {
                let nearbyEnds = firstEnd...lastEnd
                if let match = nearbyEnds.filter({ end in
                    speech[(end - anchor.count)..<end].elementsEqual(anchor)
                }).min(by: { abs($0 - boundary) < abs($1 - boundary) }) {
                    return match
                }
            }
        }
        return min(boundary, speech.count)
    }

    private func nextAnchor(in speech: ArraySlice<Character>) -> (index: Int, start: Int)? {
        let firstCandidate = index + 1
        let lastCandidate = min(index + 2, lines.count - 1)
        var earliest: (index: Int, start: Int)?

        for candidate in firstCandidate...lastCandidate {
            let anchor = Array(normalizedLines[candidate].prefix(22))
            guard anchor.count >= 10,
                  let match = Self.exactMatch(of: anchor, in: speech) else { continue }

            // A nearby repeated phrase is not enough evidence to jump to a different line.
            let nearbyLines = max(0, index - 1)...lastCandidate
            let isAmbiguous = nearbyLines.contains { other in
                other != candidate && Self.exactMatch(of: anchor, in: normalizedLines[other][...]) != nil
            }
            guard !isAmbiguous else { continue }

            if earliest.map({ match.lowerBound < $0.start }) ?? true {
                earliest = (candidate, match.lowerBound)
            }
        }
        return earliest
    }

    private static func completion(of line: [Character], in speech: ArraySlice<Character>) -> Int? {
        let ending = Array(line.suffix(44))
        if ending.count < 5 {
            return !ending.isEmpty && speech.elementsEqual(ending) ? speech.endIndex : nil
        }
        if let match = exactMatch(of: ending, in: speech) { return match.upperBound }

        // Allow a distinctive ending to complete a longer line after the speaker paraphrases it.
        if ending.count >= 28 {
            let distinctiveEnding = Array(ending.suffix(22))
            if let match = exactMatch(of: distinctiveEnding, in: speech) { return match.upperBound }
        }

        // Require the final few characters as an anchor so an incomplete partial does not scroll.
        guard ending.count >= 10 else { return nil }
        return fuzzyEnd(of: ending, in: speech, maximumEdits: max(1, ending.count / 6))
    }

    private static func exactMatch(of phrase: [Character], in speech: ArraySlice<Character>) -> Range<Int>? {
        guard !phrase.isEmpty, speech.count >= phrase.count else { return nil }
        for start in speech.startIndex...(speech.endIndex - phrase.count) {
            let end = start + phrase.count
            if speech[start..<end].elementsEqual(phrase) { return start..<end }
        }
        return nil
    }

    /// Find a credible incomplete cue prefix anywhere in the recent speech.
    private static func matchedPrefixLength(of line: [Character], in speech: ArraySlice<Character>) -> Int {
        let limit = line.count - 1
        let startsInKorean = line.prefix(3).allSatisfy {
            $0.unicodeScalars.first.map { (0xAC00...0xD7A3).contains($0.value) } ?? false
        }
        let minimum = startsInKorean ? 3 : 5
        guard limit >= minimum, speech.count >= minimum else { return 0 }

        // Free leading transcript text lets a reading start after an ad-lib.
        var previous = Array(0...limit)
        var current = previous
        var longest = 0
        for position in speech.indices {
            current[0] = 0
            for length in 1...limit {
                let isSameCharacter = speech[position] == line[length - 1]
                current[length] = min(
                    previous[length - 1] + (isSameCharacter ? 0 : 1),
                    previous[length] + 1,
                    current[length - 1] + 1
                )
                guard length >= minimum, length > longest else { continue }
                let distance = current[length]
                let isCloseMatch = length >= 10 && distance <= length / 8
                    && position - speech.startIndex >= 2
                    && speech[(position - 2)...position].elementsEqual(line[(length - 3)..<length])
                if distance == 0 || isCloseMatch {
                    longest = length
                }
            }
            if longest == limit { return longest }
            swap(&previous, &current)
        }
        return longest
    }

    /// Edit distance against substrings of the live transcript, with zero cost for a discarded prefix.
    private static func fuzzyEnd(
        of phrase: [Character], in speech: ArraySlice<Character>, maximumEdits: Int
    ) -> Int? {
        guard speech.count >= phrase.count - maximumEdits else { return nil }
        let tail = phrase.suffix(4)
        var previous = Array(0...phrase.count)
        var current = previous
        var bestDistance = maximumEdits + 1
        var bestEnd: Int?

        for position in speech.indices {
            current[0] = 0
            for letter in phrase.indices {
                let substitution = previous[letter] + (speech[position] == phrase[letter] ? 0 : 1)
                current[letter + 1] = min(substitution, previous[letter + 1] + 1, current[letter] + 1)
            }
            let end = position + 1
            let distance = current[phrase.count]
            if distance < bestDistance, end - speech.startIndex >= tail.count,
               speech[(end - tail.count)..<end].elementsEqual(tail) {
                bestDistance = distance
                bestEnd = end
            }
            swap(&previous, &current)
        }
        return bestEnd
    }

    private static func normalize(_ phrase: String) -> [Character] {
        Array(phrase.precomposedStringWithCanonicalMapping.lowercased().filter {
            $0.isLetter || $0.isNumber
        })
    }
}
