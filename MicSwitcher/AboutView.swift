//
//  AboutView.swift
//  MicSwitcher
//
//  About window showing app info, author, and disclaimers
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // App icon and name
            VStack(spacing: 10) {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)
                
                Text("MicSwitcher")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Version 1.0.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Author and purpose
            VStack(spacing: 15) {
                Text("By Matthias Götzke")
                    .font(.headline)
                
                Text("Written with Grok 4 and Claude")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("I created this simple tool to solve my own problem of constantly switching between microphones. If you're like me and need to switch audio inputs frequently, I hope this helps!")
                    .multilineTextAlignment(.center)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // GitHub link
            VStack(spacing: 10) {
                Text("Want to contribute or report bugs?")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Link("Visit GitHub Repository", destination: URL(string: "https://github.com/matthiasg/mic-switcher")!)
                    .font(.caption)
                
                Text("Pull requests are welcome! Issues without PRs might be read, time permitting.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Divider()
            
            // Disclaimer
            VStack(spacing: 10) {
                Text("DISCLAIMER")
                    .font(.caption)
                    .fontWeight(.bold)
                
                Text("This software is provided \"as is\", without warranty of any kind, express or implied. The author assumes no liability for any damages arising from the use of this software.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text("NO WARRANTIES • NO LIABILITY • USE AT YOUR OWN RISK")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Text("© 2025 Matthias Götzke")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 5)
            }
            
            Spacer()
            
            Button("OK") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(width: 550, height: 580)
    }
}

#Preview {
    AboutView()
}
