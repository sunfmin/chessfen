import Testing

@testable import Chessfen

/// The pull-up card stays where the finger left it. The old behaviour snapped to a peek or a
/// full raise; these numbers are the spec that it does not.
@Suite
struct DeckLiftSpec {
    @Test("a pull up leaves the card at that height, not snapped to the top")
    func pullUpStays() {
        #expect(DeckLift.settled(lift: 0, drag: 80, maxLift: 400) == 80)
        #expect(DeckLift.settled(lift: 0, drag: 399, maxLift: 400) == 399)
    }

    @Test("a pull down shortens it, and stops at the peek")
    func pullDownShortens() {
        #expect(DeckLift.settled(lift: 80, drag: -40, maxLift: 400) == 40)
        #expect(DeckLift.settled(lift: 80, drag: -200, maxLift: 400) == 0)
    }

    @Test("it cannot go past the board's top edge")
    func cappedAtTheBoard() {
        #expect(DeckLift.settled(lift: 300, drag: 200, maxLift: 400) == 400)
        #expect(DeckLift.settled(lift: 0, drag: 500, maxLift: 400) == 400)
    }
}
