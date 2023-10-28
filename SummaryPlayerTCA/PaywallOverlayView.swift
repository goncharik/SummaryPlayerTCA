//
//  PaywallOverlayView.swift
//  SummaryPlayerTCA
//
//  Created by Eugene Honcharenko on 2023-10-27.
//

import SwiftUI

struct PaywallOverlayView: View {
    var title: String
    var description: String
    var actionText: String
    var action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(gradient: Gradient(colors: [.clear, .white]), startPoint: .top, endPoint: .bottom)
                .frame(height: 150)

            VStack {
                Text(title)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                    .padding()

                Text(description)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.black)
                    .padding()

                Button(action: action) {
                    Text(actionText)
                        .font(.headline)
                        .fontWeight(.bold)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(10)
                        .foregroundColor(.white)
                }
                .padding()
            }
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .edgesIgnoringSafeArea(.all)
        }
    }
}

#Preview {
    ZStack(alignment: .bottom) {
        ContentView()
            .background(Color.red)

        PaywallOverlayView(
            title: "Title",
            description: "Description",
            actionText: "Action",
            action: {}
        )
    }
}
