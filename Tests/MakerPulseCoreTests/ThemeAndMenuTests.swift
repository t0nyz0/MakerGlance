import XCTest
@testable import MakerPulseCore

final class ThemeAndMenuTests: XCTestCase {
    func testDarkThemeIsNeutralCharcoalWithReadableForegrounds() {
        XCTAssertLessThan(ThemeColors.darkCanvas.luminance, 0.03)
        XCTAssertLessThan(ThemeColors.darkSurface.luminance, 0.04)
        for color in [ThemeColors.darkCanvas, ThemeColors.darkSurface, ThemeColors.darkSidebar] {
            XCTAssertLessThan(max(color.red, color.green, color.blue) - min(color.red, color.green, color.blue), 0.04)
            XCTAssertGreaterThan(ThemeRGB(0xFFFFFF).contrast(with: color), 14)
            XCTAssertGreaterThanOrEqual(ThemeColors.darkSecondary.contrast(with: color), 4.5)
        }
    }
    func testLightAndDarkTextAndChartColorsMeetAAContrast() {
        for color in ThemeColors.lightTextColors { XCTAssertGreaterThanOrEqual(color.contrast(with: ThemeColors.lightSurface), 4.5) }
        for color in ThemeColors.darkTextColors { XCTAssertGreaterThanOrEqual(color.contrast(with: ThemeColors.darkSurface), 4.5) }
    }
    func testPrimaryButtonsAndSelectedControlContrast() {
        XCTAssertGreaterThanOrEqual(ThemeRGB(0xFFFFFF).contrast(with: ThemeColors.freshPill), 4.5)
        XCTAssertGreaterThanOrEqual(ThemeRGB(0xFFFFFF).contrast(with: ThemeColors.printPill), 4.5)
        XCTAssertGreaterThanOrEqual(ThemeRGB(0xFFFFFF).contrast(with: ThemeColors.lightAccent), 4.5)
        XCTAssertGreaterThanOrEqual(ThemeRGB(0x000000).contrast(with: ThemeColors.darkAccent), 4.5)
        XCTAssertGreaterThanOrEqual(ThemeColors.lightAccent.contrast(with: ThemeColors.lightCanvas), 3)
        XCTAssertGreaterThanOrEqual(ThemeColors.darkAccent.contrast(with: ThemeColors.darkCanvas), 3)
        XCTAssertGreaterThanOrEqual(ThemeRGB(0xFFFFFF).contrast(with: ThemeColors.darkControlFill), 4.5)
        XCTAssertGreaterThanOrEqual(ThemeRGB(0xFFFFFF).contrast(with: ThemeColors.lightControlFill), 4.5)
        XCTAssertGreaterThanOrEqual(ThemeColors.darkControlFill.contrast(with: ThemeColors.darkSurface), 3)
    }
    func testMenuBadgeIsBoundedAndAttentionDistinctFromRefresh() {
        XCTAssertNil(MenuStatus(unread: -1, refreshing: false, attention: false).badge)
        XCTAssertEqual(MenuStatus(unread: 5, refreshing: false, attention: false).badge, "5")
        XCTAssertEqual(MenuStatus(unread: 1000, refreshing: false, attention: false).badge, "99+")
        XCTAssertEqual(MenuStatus(unread: 0, refreshing: true, attention: false).symbol, "arrow.triangle.2.circlepath")
        let attention = MenuStatus(unread: 3, refreshing: true, attention: true)
        XCTAssertEqual(attention.symbol, "exclamationmark.circle")
        XCTAssertTrue(attention.accessibility.contains("3 unread")); XCTAssertTrue(attention.accessibility.contains("refreshing"))
    }
}
