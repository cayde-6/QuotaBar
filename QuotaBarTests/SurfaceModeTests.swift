import Testing

@Suite("SurfaceMode")
struct SurfaceModeTests {
    @Test(
        "showsMenuBar(railHasContent:) matrix across every mode and rail content state",
        arguments: [
            (mode: SurfaceMode.menuBar, railHasContent: true, expected: true),
            (mode: SurfaceMode.menuBar, railHasContent: false, expected: true),
            (mode: SurfaceMode.rail, railHasContent: true, expected: false),
            (mode: SurfaceMode.rail, railHasContent: false, expected: true),
            (mode: SurfaceMode.both, railHasContent: true, expected: true),
            (mode: SurfaceMode.both, railHasContent: false, expected: true),
        ]
    )
    func showsMenuBar(_ input: (mode: SurfaceMode, railHasContent: Bool, expected: Bool)) {
        #expect(input.mode.showsMenuBar(railHasContent: input.railHasContent) == input.expected)
    }
}
