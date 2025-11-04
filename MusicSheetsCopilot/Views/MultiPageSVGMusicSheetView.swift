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

    var body: some View {
        ScrollView(.vertical) {
            CombinedSVGWebView(svgPages: svgPages)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItemGroup {
                Text("\(svgPages.count) page\(svgPages.count == 1 ? "" : "s")")
                    .foregroundColor(.secondary)
            }
        }
    }
}

/// Single WebView that displays all SVG pages
struct CombinedSVGWebView: View {
    let svgPages: [String]

    var body: some View {
        #if os(macOS)
        CombinedSVGWebViewMac(svgPages: svgPages)
            .frame(maxWidth: .infinity, minHeight: 800)
        #else
        CombinedSVGWebViewiOS(svgPages: svgPages)
            .frame(maxWidth: .infinity, minHeight: 800)
        #endif
    }
}

#if os(macOS)
struct CombinedSVGWebViewMac: NSViewRepresentable {
    let svgPages: [String]

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = createHTML(svgPages: svgPages)
        print("CombinedSVGWebViewMac - Loading \(svgPages.count) page(s)")
        print("CombinedSVGWebViewMac - Total HTML length: \(html.count)")
        print("CombinedSVGWebViewMac - HTML preview (first 1000 chars):")
        print(String(html.prefix(1000)))
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func createHTML(svgPages: [String]) -> String {
        let svgContent = svgPages.enumerated().map { index, svg in
            """
            <div class="page">
                <div class="page-label">Page \(index + 1)</div>
                \(svg)
            </div>
            """
        }.joined(separator: "\n")

        return """
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
                    flex-direction: column;
                    align-items: center;
                    gap: 30px;
                }
                .page {
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                    gap: 10px;
                }
                .page-label {
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    font-size: 12px;
                    color: #666;
                    margin-bottom: 5px;
                }
                svg {
                    max-width: 100%;
                    height: auto;
                    display: block;
                }
            </style>
        </head>
        <body>
            \(svgContent)
        </body>
        </html>
        """
    }
}
#else
struct CombinedSVGWebViewiOS: UIViewRepresentable {
    let svgPages: [String]

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let html = createHTML(svgPages: svgPages)
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func createHTML(svgPages: [String]) -> String {
        let svgContent = svgPages.enumerated().map { index, svg in
            """
            <div class="page">
                <div class="page-label">Page \(index + 1)</div>
                \(svg)
            </div>
            """
        }.joined(separator: "\n")

        return """
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
                    flex-direction: column;
                    align-items: center;
                    gap: 30px;
                }
                .page {
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                    gap: 10px;
                }
                .page-label {
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    font-size: 12px;
                    color: #666;
                    margin-bottom: 5px;
                }
                svg {
                    max-width: 100%;
                    height: auto;
                    display: block;
                }
            </style>
        </head>
        <body>
            \(svgContent)
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
