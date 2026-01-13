import HotwireNative
import UIKit

extension HotwireTab {
    static let all: [HotwireTab] = [
        .home,
        .components,
        .resources
    ]

    private static let baseURL = URL(string: "https://hotwire-native-demo.dev")!

    static let home = HotwireTab(
        title: "Home",
        image: UIImage(systemName: "house")!,
        url: baseURL
    )

    static let components = HotwireTab(
        title: "Components",
        image: UIImage(systemName: "square.grid.2x2")!,
        url: baseURL.appendingPathComponent("components")
    )

    static let resources = HotwireTab(
        title: "Resources",
        image: UIImage(systemName: "book.closed")!,
        url: baseURL.appendingPathComponent("resources")
    )
}
