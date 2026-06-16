import Flutter
import UIKit

final class RenderScenePlaceholderFactory: NSObject, FlutterPlatformViewFactory {
  static let viewType = "tbe/render_scene_view"

  static func register(with registry: FlutterPluginRegistry) {
    registry.register(RenderScenePlaceholderFactory(), withId: viewType)
  }

  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    RenderScenePlaceholderView(frame: frame, viewId: viewId, args: args)
  }
}

final class RenderScenePlaceholderView: NSObject, FlutterPlatformView {
  private let container: UIView

  init(frame: CGRect, viewId: Int64, args: Any?) {
    container = UIView(frame: frame)
    container.backgroundColor = UIColor.secondarySystemBackground

    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.numberOfLines = 0
    label.textAlignment = .center
    label.textColor = .secondaryLabel
    label.text = """
    RenderScene native viewport placeholder
    (iOS skeleton only)
    """
    container.addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      label.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 16),
      label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),
    ])

    super.init()
  }

  func view() -> UIView {
    container
  }
}
