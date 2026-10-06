import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            ControlBarView()
                .frame(height: 196)

            GridSurfaceRepresentable()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.appBackground)
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            appState.start()
        }
    }
}
