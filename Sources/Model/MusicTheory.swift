import Foundation

// MARK: - Scale

struct Scale: Identifiable, Hashable {
    /// Western / descriptive name. Unique — used as the identity.
    let name: String
    /// Carnatic raga with the same pitch set, when there is one. Shown first
    /// in the UI because the classical name is what this audience reaches for.
    var raga: String? = nil
    /// Semitone offsets from the root within one octave, ascending.
    let intervals: [Int]

    var id: String { name }

    var displayTitle: String { raga ?? name }
    var displaySubtitle: String? { raga == nil ? nil : name }

    static let all: [Scale] = [
        Scale(name: "Major",            raga: "Shankarabharanam", intervals: [0, 2, 4, 5, 7, 9, 11]),
        Scale(name: "Natural Minor",    raga: "Natabhairavi",     intervals: [0, 2, 3, 5, 7, 8, 10]),
        Scale(name: "Major Pentatonic", raga: "Mohanam",          intervals: [0, 2, 4, 7, 9]),
        Scale(name: "Minor Pentatonic", raga: "Shuddha Dhanyasi", intervals: [0, 3, 5, 7, 10]),
        Scale(name: "Blues",                                      intervals: [0, 3, 5, 6, 7, 10]),
        Scale(name: "Dorian",           raga: "Kharaharapriya",   intervals: [0, 2, 3, 5, 7, 9, 10]),
        Scale(name: "Phrygian",         raga: "Hanumatodi",       intervals: [0, 1, 3, 5, 7, 8, 10]),
        Scale(name: "Mixolydian",       raga: "Harikambhoji",     intervals: [0, 2, 4, 5, 7, 9, 10]),
        Scale(name: "Mixolydian \u{266D}6", raga: "Charukesi",      intervals: [0, 2, 4, 5, 7, 8, 10]),
    ]
}

// MARK: - Root note

enum RootNote: Int, CaseIterable, Identifiable {
    case c = 0, cSharp, d, dSharp, e, f, fSharp, g, gSharp, a, aSharp, b

    var id: Int { rawValue }

    /// Naturals only — the root keyboard lays these out as white keys.
    var isNatural: Bool { NoteName.names[rawValue].count == 1 }

    var displayName: String {
        NoteName.names[rawValue]
    }
}

// MARK: - Grid layout (rows offset in fourths, LinnStrument-style)

struct GridLayout: Equatable {
    let rows: Int
    let cols: Int
    /// MIDI note of the bottom-left cell.
    let baseMidi: Int
    /// Semitones between adjacent rows (5 = perfect fourth).
    let rowInterval: Int

    /// Portrait-oriented square-cell grid. 8 cols × 10 rows.
    /// Bottom-left = E2 (MIDI 40); top-left = MIDI 85 (~D6). Rows in fourths.
    static let standard = GridLayout(rows: 10, cols: 8, baseMidi: 40, rowInterval: 5)

    /// Row 0 is the BOTTOM row (like strings on an instrument).
    func midiNote(row: Int, col: Int) -> Int {
        baseMidi + row * rowInterval + col
    }

    func pitchClass(row: Int, col: Int) -> Int {
        ((midiNote(row: row, col: col) % 12) + 12) % 12
    }
}

// MARK: - Scale membership coloring

struct ScaleColoring: Equatable {
    let rootPitchClass: Int
    let inScalePitchClasses: Set<Int>

    init(scale: Scale, root: RootNote) {
        rootPitchClass = root.rawValue
        inScalePitchClasses = Set(scale.intervals.map { ($0 + root.rawValue) % 12 })
    }

    enum CellKind { case root, inScale, outOfScale }

    func kind(forPitchClass pc: Int) -> CellKind {
        if pc == rootPitchClass { return .root }
        if inScalePitchClasses.contains(pc) { return .inScale }
        return .outOfScale
    }
}

// MARK: - Note naming

enum NoteName {
    /// Proper sharp glyph — reads as notation, not as a hashtag.
    static let names = ["C", "C\u{266F}", "D", "D\u{266F}", "E", "F",
                        "F\u{266F}", "G", "G\u{266F}", "A", "A\u{266F}", "B"]

    static func name(forMidi midi: Int) -> String {
        names[((midi % 12) + 12) % 12]
    }

    /// Scientific pitch octave (C4 = MIDI 60).
    static func octave(forMidi midi: Int) -> Int {
        Int(floor(Double(midi) / 12.0)) - 1
    }
}
