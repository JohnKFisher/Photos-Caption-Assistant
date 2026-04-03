import SwiftUI
import XCTest
@testable import PhotosCaptionAssistant

final class ImmersivePreviewLayoutCalculatorTests: XCTestCase {
    func testWideLandscapePhotoChoosesOverlay() {
        let layout = ImmersivePreviewLayoutCalculator.calculate(
            viewportSize: CGSize(width: 1440, height: 900),
            safeAreaInsets: .init(),
            mediaSize: CGSize(width: 3840, height: 2160)
        )

        XCTAssertEqual(layout.layoutMode, .overlay)
        XCTAssertEqual(layout.mediaSizingMode, .aspectFill)
        XCTAssertTrue(rect(layout.topBarRect, fitsInside: layout.mediaRect))
        XCTAssertTrue(rect(layout.bottomPanelRect, fitsInside: layout.mediaRect))
    }

    func testTallPortraitPhotoChoosesBottomShelf() {
        let layout = ImmersivePreviewLayoutCalculator.calculate(
            viewportSize: CGSize(width: 1440, height: 900),
            safeAreaInsets: .init(),
            mediaSize: CGSize(width: 3024, height: 4032)
        )

        XCTAssertEqual(layout.layoutMode, .bottomShelf)
        XCTAssertEqual(layout.mediaSizingMode, .aspectFit)
        XCTAssertGreaterThan(layout.mediaRect.minY, layout.topBarRect.maxY)
        XCTAssertLessThan(layout.mediaRect.maxY, layout.bottomPanelRect.minY)
    }

    func testLandscapeVideoChoosesOverlay() {
        let layout = ImmersivePreviewLayoutCalculator.calculate(
            viewportSize: CGSize(width: 1728, height: 1117),
            safeAreaInsets: EdgeInsets(top: 28, leading: 0, bottom: 18, trailing: 0),
            mediaSize: CGSize(width: 1920, height: 1080)
        )

        XCTAssertEqual(layout.layoutMode, .overlay)
        XCTAssertEqual(layout.mediaSizingMode, .aspectFill)
    }

    func testNarrowViewportForcesBottomShelf() {
        let layout = ImmersivePreviewLayoutCalculator.calculate(
            viewportSize: CGSize(width: 960, height: 740),
            safeAreaInsets: .init(),
            mediaSize: CGSize(width: 3840, height: 2160)
        )

        XCTAssertEqual(layout.layoutMode, .bottomShelf)
        XCTAssertEqual(layout.mediaSizingMode, .aspectFit)
    }

    func testReturnedFramesStayInsideSafeViewport() {
        let safeAreaInsets = EdgeInsets(top: 30, leading: 12, bottom: 20, trailing: 16)
        let layout = ImmersivePreviewLayoutCalculator.calculate(
            viewportSize: CGSize(width: 1512, height: 982),
            safeAreaInsets: safeAreaInsets,
            mediaSize: CGSize(width: 3024, height: 4032)
        )

        let safeViewport = CGRect(
            x: safeAreaInsets.leading,
            y: safeAreaInsets.top,
            width: 1512 - safeAreaInsets.leading - safeAreaInsets.trailing,
            height: 982 - safeAreaInsets.top - safeAreaInsets.bottom
        )

        XCTAssertTrue(rect(layout.topBarRect, fitsInside: safeViewport))
        XCTAssertTrue(rect(layout.bottomPanelRect, fitsInside: safeViewport))
        XCTAssertTrue(rect(layout.mediaRect, fitsInside: layout.mediaContainerRect))
        XCTAssertTrue(rect(layout.mediaContainerRect, fitsInside: safeViewport))
    }

    private func rect(_ rect: CGRect, fitsInside container: CGRect) -> Bool {
        rect.minX >= container.minX - 0.5
            && rect.maxX <= container.maxX + 0.5
            && rect.minY >= container.minY - 0.5
            && rect.maxY <= container.maxY + 0.5
    }
}
