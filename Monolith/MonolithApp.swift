import SwiftUI

@main
struct MonolithApp: App {
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Initialize the camera in the background
                ContentView()
                
                if showSplash {
                    ZStack {
                        Color.black
                            .ignoresSafeArea()
                        
                        Image("splash-screen")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity) // Force expansion
                            .ignoresSafeArea()
                    }
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                showSplash = false
                            }
                        }
                    }
                }
            }
        }
    }
}
