import SwiftUI
import WebKit

/// SwiftUI view that displays multiple pages of SVG music notation vertically
struct MultiPageSVGMusicSheetView: View {
    let svgPages: [String]
    let timingData: String
    @ObservedObject var midiPlayer: MIDIPlayer
    @ObservedObject var metronome: Metronome
    let playbackMode: ContentView.PlaybackMode
    @EnvironmentObject var verovioService: VerovioService

    var body: some View {
        // Use metronome's currentTime in metronome-only mode, otherwise use MIDI player's time
        let currentTime = playbackMode == .metronomeOnly ? metronome.currentTime : midiPlayer.currentTime
        let isPlaying = playbackMode == .metronomeOnly ? metronome.isTicking : midiPlayer.isPlaying

        ScrollView(.vertical) {
            CombinedSVGWebView(svgPages: svgPages, timingData: timingData, currentTime: currentTime, isPlaying: isPlaying)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Single WebView that displays all SVG pages
struct CombinedSVGWebView: View {
    let svgPages: [String]
    let timingData: String
    let currentTime: TimeInterval
    let isPlaying: Bool
    @EnvironmentObject var verovioService: VerovioService
    @EnvironmentObject var midiPlayer: MIDIPlayer

    var body: some View {
        #if os(macOS)
        CombinedSVGWebViewMac(svgPages: svgPages, timingData: timingData, currentTime: currentTime, isPlaying: isPlaying)
            .frame(maxWidth: .infinity, minHeight: 800)
        #else
        CombinedSVGWebViewiOS(svgPages: svgPages, timingData: timingData, currentTime: currentTime, isPlaying: isPlaying)
            .frame(maxWidth: .infinity, minHeight: 800)
        #endif
    }
}

#if os(macOS)
struct CombinedSVGWebViewMac: NSViewRepresentable {
    let svgPages: [String]
    let timingData: String
    let currentTime: TimeInterval
    let isPlaying: Bool
    @EnvironmentObject var verovioService: VerovioService
    @EnvironmentObject var midiPlayer: MIDIPlayer

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "noteClickHandler")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Store references in coordinator
        context.coordinator.verovioService = verovioService
        context.coordinator.midiPlayer = midiPlayer

        // Only reload HTML if pages changed (not on every time update)
        if context.coordinator.currentPages != svgPages {
            let html = createHTML(svgPages: svgPages, timingData: timingData)
            webView.loadHTMLString(html, baseURL: nil)
            context.coordinator.currentPages = svgPages
        }

        // Update highlighting based on playback time
        let progressMs = currentTime * 1000  // Convert to milliseconds
        if isPlaying {
            let script = "updatePlaybackHighlight(\(progressMs));"
            webView.evaluateJavaScript(script, completionHandler: nil)
        } else if currentTime > 0 {
            // Update highlighting even when paused to show the current position
            let script = "updatePlaybackHighlight(\(progressMs));"
            webView.evaluateJavaScript(script, completionHandler: nil)
        } else {
            // Clear highlighting when stopped at beginning
            webView.evaluateJavaScript("clearPlaybackHighlight();", completionHandler: nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKScriptMessageHandler {
        var currentPages: [String] = []
        weak var verovioService: VerovioService?
        weak var midiPlayer: MIDIPlayer?

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "noteClickHandler",
                  let noteId = message.body as? String else { return }


            // Find the start time for this note
            if let startTime = verovioService?.getNoteStartTime(noteId) {
                midiPlayer?.seek(to: startTime)
            }
        }
    }

    private func createHTML(svgPages: [String], timingData: String) -> String {
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
                    width: 100%;
                }
                .page-label {
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    font-size: 12px;
                    color: #666;
                    margin-bottom: 5px;
                }
                svg {
                    width: 100%;
                    height: auto;
                    display: block;
                }
                .highlighted-note {
                    fill: #ff6b6b !important;
                    opacity: 0.8;
                }
            </style>
            <script>
                // Parse Verovio timing data
                const timingData = \(timingData);
                let currentHighlightedElements = [];

                console.log('Timing data:', timingData);
                console.log('Type:', typeof timingData, 'Array?', Array.isArray(timingData));

                function updatePlaybackHighlight(timeMs) {
                    clearPlaybackHighlight();

                    console.log('Highlighting at time:', timeMs);

                    // Find all notes that should be highlighted at current time
                    if (!timingData || !Array.isArray(timingData)) {
                        console.log('No valid timing data');
                        return;
                    }

                    let highlightCount = 0;

                    // Verovio timing data structure:
                    // Each entry has: tstamp (timestamp in ms), on (array of IDs turning on), off (array of IDs turning off)
                    // We need to track which notes are currently active
                    let currentIndex = 0;
                    const activeNotes = new Set();

                    // Process all timing entries up to current time
                    for (let i = 0; i < timingData.length; i++) {
                        const entry = timingData[i];
                        if (entry.tstamp > timeMs) break;

                        // Add notes that turn on
                        if (entry.on) {
                            entry.on.forEach(id => activeNotes.add(id));
                        }

                        // Remove notes that turn off
                        if (entry.off) {
                            entry.off.forEach(id => activeNotes.delete(id));
                        }
                    }

                    // Highlight all active notes
                    activeNotes.forEach(id => {
                        const elements = document.querySelectorAll(`[*|id="${id}"]`);
                        elements.forEach(el => {
                            el.classList.add('highlighted-note');
                            currentHighlightedElements.push(el);
                            highlightCount++;
                        });
                    });

                    console.log(`Highlighted ${highlightCount} elements from ${activeNotes.size} active notes`);
                }

                function clearPlaybackHighlight() {
                    currentHighlightedElements.forEach(el => {
                        el.classList.remove('highlighted-note');
                    });
                    currentHighlightedElements = [];
                }

                // Initialize click handlers when page loads
                window.addEventListener('load', function() {
                    console.log('Setting up click handlers for notes');

                    // Find all note elements and make them clickable
                    // Verovio notes typically have class 'note' or are within elements with timing data
                    const noteElements = document.querySelectorAll('.note, [class*="note"]');
                    console.log(`Found ${noteElements.length} note elements`);

                    // Also add handlers for all elements that have IDs in our timing data
                    if (timingData && Array.isArray(timingData)) {
                        const allNoteIds = new Set();
                        timingData.forEach(entry => {
                            if (entry.on) {
                                entry.on.forEach(id => allNoteIds.add(id));
                            }
                        });

                        console.log(`Found ${allNoteIds.size} unique note IDs in timing data`);

                        allNoteIds.forEach(noteId => {
                            const elements = document.querySelectorAll(`[*|id="${noteId}"]`);
                            elements.forEach(el => {
                                el.style.cursor = 'pointer';
                                el.addEventListener('click', function(e) {
                                    e.stopPropagation();
                                    console.log('Clicked note:', noteId);
                                    window.webkit.messageHandlers.noteClickHandler.postMessage(noteId);
                                });
                            });
                        });
                    }
                });
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
    let timingData: String
    let currentTime: TimeInterval
    let isPlaying: Bool
    @EnvironmentObject var verovioService: VerovioService
    @EnvironmentObject var midiPlayer: MIDIPlayer

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "noteClickHandler")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        // Disable zooming
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 1.0
        webView.scrollView.bouncesZoom = false

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Store references in coordinator
        context.coordinator.verovioService = verovioService
        context.coordinator.midiPlayer = midiPlayer

        // Only reload HTML if pages changed
        if context.coordinator.currentPages != svgPages {
            let html = createHTML(svgPages: svgPages, timingData: timingData)
            webView.loadHTMLString(html, baseURL: nil)
            context.coordinator.currentPages = svgPages
        }

        // Update highlighting based on playback time
        let progressMs = currentTime * 1000
        if isPlaying {
            let script = "updatePlaybackHighlight(\(progressMs));"
            webView.evaluateJavaScript(script, completionHandler: nil)
        } else if currentTime > 0 {
            // Update highlighting even when paused to show the current position
            let script = "updatePlaybackHighlight(\(progressMs));"
            webView.evaluateJavaScript(script, completionHandler: nil)
        } else {
            webView.evaluateJavaScript("clearPlaybackHighlight();", completionHandler: nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKScriptMessageHandler {
        var currentPages: [String] = []
        weak var verovioService: VerovioService?
        weak var midiPlayer: MIDIPlayer?

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "noteClickHandler",
                  let noteId = message.body as? String else { return }


            // Find the start time for this note
            if let startTime = verovioService?.getNoteStartTime(noteId) {
                midiPlayer?.seek(to: startTime)
            }
        }
    }

    private func createHTML(svgPages: [String], timingData: String) -> String {
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
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                * {
                    box-sizing: border-box;
                }
                html, body {
                    width: 100%;
                    overflow-x: hidden;
                }
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
                    width: 100%;
                    max-width: 100%;
                }
                .page-label {
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    font-size: 12px;
                    color: #666;
                    margin-bottom: 5px;
                }
                svg {
                    width: 100% !important;
                    height: auto !important;
                    max-width: 100%;
                    display: block;
                }
                .highlighted-note {
                    fill: #ff6b6b !important;
                    opacity: 0.8;
                }
            </style>
            <script>
                // Parse Verovio timing data
                const timingData = \(timingData);
                let currentHighlightedElements = [];

                function updatePlaybackHighlight(timeMs) {
                    console.log("updatePlaybackHighlight called with time:", timeMs);
                    clearPlaybackHighlight();

                    // Find all notes that should be active at current time
                    if (!timingData || !Array.isArray(timingData)) {
                        console.log("No timing data available");
                        return;
                    }

                    // Build set of currently active note IDs
                    const activeNotes = new Set();

                    for (const entry of timingData) {
                        if (entry.tstamp > timeMs) break; // Stop when we reach future events

                        // Add notes that start at this event
                        if (entry.on && Array.isArray(entry.on)) {
                            entry.on.forEach(id => activeNotes.add(id));
                        }

                        // Remove notes that end at this event
                        if (entry.off && Array.isArray(entry.off)) {
                            entry.off.forEach(id => activeNotes.delete(id));
                        }
                    }

                    console.log("Active notes:", Array.from(activeNotes));

                    // Highlight all currently active notes
                    activeNotes.forEach(noteId => {
                        const elements = document.querySelectorAll(`[*|id="${noteId}"]`);
                        console.log(`Found ${elements.length} elements for note ${noteId}`);
                        elements.forEach(el => {
                            el.classList.add('highlighted-note');
                            currentHighlightedElements.push(el);
                        });
                    });
                }

                function clearPlaybackHighlight() {
                    currentHighlightedElements.forEach(el => {
                        el.classList.remove('highlighted-note');
                    });
                    currentHighlightedElements = [];
                }

                // Initialize click handlers when page loads
                window.addEventListener('load', function() {
                    console.log('Setting up click handlers for notes');

                    // Add handlers for all elements that have IDs in our timing data
                    if (timingData && Array.isArray(timingData)) {
                        const allNoteIds = new Set();
                        timingData.forEach(entry => {
                            if (entry.on) {
                                entry.on.forEach(id => allNoteIds.add(id));
                            }
                        });

                        console.log(`Found ${allNoteIds.size} unique note IDs in timing data`);

                        allNoteIds.forEach(noteId => {
                            const elements = document.querySelectorAll(`[*|id="${noteId}"]`);
                            elements.forEach(el => {
                                el.style.cursor = 'pointer';
                                el.addEventListener('click', function(e) {
                                    e.stopPropagation();
                                    console.log('Clicked note:', noteId);
                                    window.webkit.messageHandlers.noteClickHandler.postMessage(noteId);
                                });
                            });
                        });
                    }
                });
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
