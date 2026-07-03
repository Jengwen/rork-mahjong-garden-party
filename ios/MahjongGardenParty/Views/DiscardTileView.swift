import SwiftUI

struct DiscardTileView: View {
    let tile: MahjongTile
    let discardedBy: String?
    var isIPad: Bool = false

    var body: some View {
        TileView(tile: tile, size: isIPad ? .iPadSmall : .small)
    }
}
