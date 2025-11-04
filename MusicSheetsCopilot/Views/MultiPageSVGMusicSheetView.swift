//
//  MultiPageSVGMusicSheetView.swift
//  MusicSheetsCopilot
//
//  Created on November 4, 2025.
//

import SwiftUI
import WebKit

/// SwiftUI view that displays multiple pages of SVG music notation vertically
struct MultiPageSVGMusicSheetView: View {
    let svgPages: [String]

    @State private var scale: CGFloat = 1.0

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(spacing: 20) {
                ForEach(Array(svgPages.enumerated()), id: \.offset) { index, svgString in
                    VStack(spacing: 5) {
                        Text("Page \(index + 1)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        SVGWebView(svgString: svgString)
                            .frame(minWidth: 600, minHeight: 400)
                    }
                }
            }
            .padding()
            .scaleEffect(scale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItemGroup {
                Button(action: { scale = max(0.5, scale - 0.1) }) {
                    Image(systemName: "minus.magnifyingglass")
                }

                Button(action: { scale = min(3.0, scale + 0.1) }) {
                    Image(systemName: "plus.magnifyingglass")
                }

                Button(action: { scale = 1.0 }) {
                    Text("100%")
                }

                Text("\(svgPages.count) page\(svgPages.count == 1 ? "" : "s")")
                    .foregroundColor(.secondary)
            }
        }
    }
}

/// UIViewRepresentable/NSViewRepresentable wrapper for WKWebView to display SVG
struct SVGWebView: View {
    let svgString: String

    var body: some View {
        #if os(macOS)
        SVGWebViewMac(svgString: svgString)
        #else
        SVGWebViewiOS(svgString: svgString)
        #endif
    }
}

#if os(macOS)
struct SVGWebViewMac: NSViewRepresentable {
    let svgString: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground") // Transparent background
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = createHTML(svg: svgString)
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func createHTML(svg: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {
                    margin: 0;
                    padding: 20px;
                    background: transparent;
                    display: flex;
                    justify-content: center;
                }
                svg {
                    max-width: 100%;
                    height: auto;
                }
            </style>
        </head>
        <body>
            \(svg)
        </body>
        </html>
        """
    }
}
#else
struct SVGWebViewiOS: UIViewRepresentable {
    let svgString: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let html = createHTML(svg: svgString)
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func createHTML(svg: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes">
            <style>
                body {
                    margin: 0;
                    padding: 20px;
                    background: transparent;
                    display: flex;
                    justify-content: center;
                }
                svg {
                    max-width: 100%;
                    height: auto;
                }
            </style>
        </head>
        <body>
            \(svg)
        </body>
        </html>
        """
    }
}
#endif

#Preview {
    MultiPageSVGMusicSheetView(svgPages: [
        """
        <svg xmlns="http://www.w3.org/2000/svg" width="200" height="100">
            <text x="100" y="50" text-anchor="middle" font-size="20">Page 1</text>
        </svg>
        """,
        """
        <svg xmlns="http://www.w3.org/2000/svg" width="200" height="100">
            <text x="100" y="50" text-anchor="middle" font-size="20">Page 2</text>
        </svg>
        """
    ])
}
