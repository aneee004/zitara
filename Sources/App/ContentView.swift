import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    /// Portrait: control bar on top. Landscape: control column on the left,
    /// keeping the sustain button under the left thumb in both.
    private let barHeight: CGFloat = 196
    private let columnWidth: CGFloat = 300
    /// Below this along the panel's long axis, the panel uses its compact
    /// arrangement. The 12.9"/13" iPads are 1024+ pt; every other iPad is under.
    private let fullPanelLength: CGFloat = 1000

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            let isCompact = (isLandscape ? geo.size.height : geo.size.width) < fullPanelLength
            // AnyLayout (not if/else) so the grid keeps its identity across
            // rotation — rebuilding it would drop an in-flight note's noteOff.
            let stack = isLandscape
                ? AnyLayout(HStackLayout(spacing: 0))
                : AnyLayout(VStackLayout(spacing: 0))

            stack {
                ControlPanelView(isLandscape: isLandscape, isCompact: isCompact)
                    .frame(width: isLandscape ? columnWidth : nil,
                           height: isLandscape ? nil : barHeight)

                GridSurfaceRepresentable(layout: isLandscape ? .landscape : .portrait)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay(alignment: .bottom) {
            if let message = appState.audioError {
                AudioErrorBanner(message: message, onRetry: appState.retryAudio)
            }
        }
        .overlay {
            if appState.showingHelp {
                HelpOverlayView(onDismiss: appState.dismissHelp)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: appState.showingHelp)
        .background(Theme.appBackground)
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            appState.start()
        }
    }
}
