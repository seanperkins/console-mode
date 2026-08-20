import CoreGraphics

struct ScreenMetrics: Sendable, Equatable {
    var visibleOriginX: CGFloat
    var visibleOriginY: CGFloat
    var visibleWidth: CGFloat
    var visibleHeight: CGFloat
}
