import XCTest
@testable import Zitara

/// Guards the invariants the rest of the app silently relies on: scale names
/// are persisted identities, intervals drive the taraf tuning, and the grid
/// mapping is what the player's muscle memory is built on.
final class MusicTheoryTests: XCTestCase {

    // MARK: Scales

    func testScaleNamesAreUnique() {
        let names = Scale.all.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "Scale.name is the identity — duplicates break persistence and the picker")
    }

    func testPersistedNamesStillExist() {
        // Names that shipped in earlier builds and may sit in UserDefaults.
        // Removing or renaming one silently resets that user's scale.
        let shipped = ["Major", "Natural Minor", "Major Pentatonic", "Minor Pentatonic",
                       "Blues", "Dorian", "Phrygian", "Mixolydian", "Mixolydian \u{266D}6"]
        let current = Set(Scale.all.map(\.name))
        for name in shipped {
            XCTAssertTrue(current.contains(name), "Persisted scale \"\(name)\" was removed or renamed")
        }
    }

    func testIntervalsStartAtRootAscendWithinOneOctave() {
        for scale in Scale.all {
            XCTAssertEqual(scale.intervals.first, 0, "\(scale.name) must start on Sa")
            XCTAssertEqual(scale.intervals, scale.intervals.sorted(), "\(scale.name) intervals must ascend")
            XCTAssertEqual(Set(scale.intervals).count, scale.intervals.count, "\(scale.name) has duplicate intervals")
            XCTAssertTrue(scale.intervals.allSatisfy { (0...11).contains($0) }, "\(scale.name) leaves the octave")
        }
    }

    func testPitchSetsAreDistinct() {
        // Two entries with the same pitch set would be the same raga twice.
        let sets = Scale.all.map { Set($0.intervals) }
        XCTAssertEqual(Set(sets).count, sets.count)
    }

    func testLaunchDefaultIsMajorPentatonic() {
        XCTAssertEqual(Scale.launchDefault.name, "Major Pentatonic")
    }

    func testNamesShowHindustaniFirst() {
        let yaman = Scale.all.first { $0.name == "Lydian" }!
        XCTAssertEqual(yaman.displayTitle, "Yaman")
        XCTAssertEqual(yaman.displaySubtitle, "Kalyani \u{00B7} Lydian")
        XCTAssertEqual(yaman.shortSubtitle, "Kalyani")

        let blues = Scale.all.first { $0.name == "Blues" }!
        XCTAssertEqual(blues.displayTitle, "Blues")
        XCTAssertNil(blues.displaySubtitle)
        XCTAssertNil(blues.shortSubtitle)
    }

    // MARK: Grid

    func testGridIsFourthsFromE2() {
        for layout in [GridLayout.portrait, .landscape] {
            XCTAssertEqual(layout.midiNote(row: 0, col: 0), 40)
            XCTAssertEqual(layout.midiNote(row: 1, col: 0), 45, "rows are a perfect fourth apart")
            XCTAssertEqual(layout.midiNote(row: 0, col: 1), 41, "columns are semitones")
        }
        XCTAssertEqual(GridLayout.portrait.midiNote(row: 9, col: 7), 92)
        XCTAssertEqual(GridLayout.landscape.midiNote(row: 8, col: 9), 89)
    }

    func testPitchClassWraps() {
        XCTAssertEqual(GridLayout.portrait.pitchClass(row: 0, col: 0), 4) // E
    }

    // MARK: Coloring

    func testColoringFollowsRootAndScale() {
        let bhupali = ScaleColoring(scale: Scale.launchDefault, root: .d)
        XCTAssertEqual(bhupali.kind(forPitchClass: 2), .root)        // D = Sa
        XCTAssertEqual(bhupali.kind(forPitchClass: 6), .inScale)     // F♯ = Ga
        XCTAssertEqual(bhupali.kind(forPitchClass: 7), .outOfScale)  // G = Ma, absent
        XCTAssertEqual(bhupali.kind(forPitchClass: 11), .inScale)    // B = Dha (9 + 2)
        XCTAssertEqual(bhupali.kind(forPitchClass: 1), .outOfScale)  // C♯ = Ni, absent
    }
}
