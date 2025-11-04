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
    @ObservedObject var midiPlayer: MIDIPlayer

    var body: some View {
        ScrollView(.vertical) {
            CombinedSVGWebView(svgPages: svgPages, currentTime: midiPlayer.currentTime, isPlaying: midiPlayer.isPlaying)
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
    let currentTime: TimeInterval
    let isPlaying: Bool

    var body: some View {
        #if os(macOS)
        CombinedSVGWebViewMac(svgPages: svgPages, currentTime: currentTime, isPlaying: isPlaying)
            .frame(maxWidth: .infinity, minHeight: 800)
        #else
        CombinedSVGWebViewiOS(svgPages: svgPages, currentTime: currentTime, isPlaying: isPlaying)
            .frame(maxWidth: .infinity, minHeight: 800)
        #endif
    }
}

#if os(macOS)
struct CombinedSVGWebViewMac: NSViewRepresentable {
    let svgPages: [String]
    let currentTime: TimeInterval
    let isPlaying: Bool

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Only reload HTML if pages changed (not on every time update)
        if context.coordinator.currentPages != svgPages {
            let html = createHTML(svgPages: svgPages)
            print("CombinedSVGWebViewMac - Loading \(svgPages.count) page(s)")
            webView.loadHTMLString(html, baseURL: nil)
            context.coordinator.currentPages = svgPages
        }

        // Update highlighting based on playback time
        if isPlaying {
            let progress = currentTime
            let script = "updatePlaybackHighlight(\(progress));"
            webView.evaluateJavaScript(script, completionHandler: nil)
        } else {
            // Clear highlighting when not playing
            webView.evaluateJavaScript("clearPlaybackHighlight();", completionHandler: nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var currentPages: [String] = []
    }

    private func createHTML(svgPages: [String]) -> String {
        let svgContent = svgPages.enumerated().map { index, svg in
            let pageLabel = svgPages.count > 1 ? "<div class=\"page-label\">Page \(index + 1)</div>" : ""
            return """
            <div class="page">
                \(pageLabel)
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
                .highlighted-note {
                    fill: #ff6b6b !important;
                    opacity: 0.8;
                }
            </style>
            <script>
                let currentHighlightedElements = [];

                function updatePlaybackHighlight(time) {
                    // Clear previous highlights
                    clearPlaybackHighlight();

                    // Get all note elements (Verovio uses class 'note' for note heads)
                    const notes = document.querySelectorAll('.note, .chord');

                    // Simple time-based highlighting (this is approximate)
                    // In a real implementation, you'd need timing data from Verovio
                    const noteIndex = Math.floor(time * 2); // Rough approximation

                    if (notes[noteIndex]) {
                        notes[noteIndex].classList.add('highlighted-note');
                        currentHighlightedElements.push(notes[noteIndex]);
                    }
                }

                function clearPlaybackHighlight() {
                    currentHighlightedElements.forEach(el => {
                        el.classList.remove('highlighted-note');
                    });
                    currentHighlightedElements = [];
                }
            </script>
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
    let currentTime: TimeInterval
    let isPlaying: Bool

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Only reload HTML if pages changed
        if context.coordinator.currentPages != svgPages {
            let html = createHTML(svgPages: svgPages)
            webView.loadHTMLString(html, baseURL: nil)
            context.coordinator.currentPages = svgPages
        }

        // Update highlighting based on playback time
        if isPlaying {
            let progress = currentTime
            let script = "updatePlaybackHighlight(\(progress));"
            webView.evaluateJavaScript(script, completionHandler: nil)
        } else {
            webView.evaluateJavaScript("clearPlaybackHighlight();", completionHandler: nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var currentPages: [String] = []
    }

    private func createHTML(svgPages: [String]) -> String {
        let svgContent = svgPages.enumerated().map { index, svg in
            let pageLabel = svgPages.count > 1 ? "<div class=\"page-label\">Page \(index + 1)</div>" : ""
            return """
            <div class="page">
                \(pageLabel)
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
                .highlighted-note {
                    fill: #ff6b6b !important;
                    opacity: 0.8;
                }
            </style>
            <script>
                let currentHighlightedElements = [];

                function updatePlaybackHighlight(time) {
                    clearPlaybackHighlight();
                    const notes = document.querySelectorAll('.note, .chord');
                    const noteIndex = Math.floor(time * 2);

                    if (notes[noteIndex]) {
                        notes[noteIndex].classList.add('highlighted-note');
                        currentHighlightedElements.push(notes[noteIndex]);
                    }
                }

                function clearPlaybackHighlight() {
                    currentHighlightedElements.forEach(el => {
                        el.classList.remove('highlighted-note');
                    });
                    currentHighlightedElements = [];
                }
            </script>
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
    ], midiPlayer: MIDIPlayer())
}
