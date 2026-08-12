# Swift becomes the only living implementation

Once the recogniser exists in Swift, the Python package is frozen: no features, no
dependency bumps, no behaviour changes. Keeping it alive as a reference implementation
and diffing the two on a golden corpus was the alternative — rejected because carrying
two implementations of one algorithm costs more than the cross-check is worth.

## Consequences

- The pytest suite stops being a safety net for the shipped product. Its *design*
  survives the port, though, and so does the asset it leans on: `reference_board.png`
  plus its expected FEN moves to the Swift tests unchanged.
- Correctness has no external oracle any more; it rests on the roundtrip property
  (render, recognise, demand the same FEN) plus that one screenshot in a foreign piece
  set. See ADR-0004 for why the screenshot carries more weight than it looks like it
  should.
- The Python CLI stays usable on a desktop, and nothing new should be built on it.
