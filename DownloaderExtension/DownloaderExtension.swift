import BackgroundAssets
import ExtensionFoundation
import StoreKit

/// Lets iOS download and update the Apple-hosted library packs while the app isn't running.
/// Every pack is on-demand, so nothing downloads until the person picks a library in the app.
@main
struct DownloaderExtension: StoreDownloaderExtension {}
