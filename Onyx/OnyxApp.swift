import SwiftUI

@main
struct OnyxApp: App {
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                
                if showSplash {
                    ZStack {
                        Color.black
                            .ignoresSafeArea()
                        
                        Image("splash-screen")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
