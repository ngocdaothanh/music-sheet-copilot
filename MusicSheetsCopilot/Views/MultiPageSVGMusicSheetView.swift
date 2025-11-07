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

        // Remove outer ScrollView to avoid double scrolling, let WKWebView handle scrolling
        CombinedSVGWebView(svgPages: svgPages, timingData: timingData, currentTime: currentTime, isPlaying: isPlaying, metronome: metronome)
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
    @ObservedObject var metronome: Metronome

    var body: some View {
        #if os(macOS)
        CombinedSVGWebViewMac(svgPages: svgPages, timingData: timingData, currentTime: currentTime, isPlaying: isPlaying, metronome: metronome)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        CombinedSVGWebViewiOS(svgPages: svgPages, timingData: timingData, currentTime: currentTime, isPlaying: isPlaying, metronome: metronome)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    @ObservedObject var metronome: Metronome

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "noteClickHandler")
        config.userContentController.add(context.coordinator, name: "measureClickHandler")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Store references in coordinator
        context.coordinator.verovioService = verovioService
        context.coordinator.midiPlayer = midiPlayer
        context.coordinator.metronome = metronome

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
        weak var metronome: Metronome?
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "noteClickHandler", let noteId = message.body as? String {
                print("[DEBUG] noteClickHandler received noteId: \(noteId)")
                // Find the start time for this note and seek directly to it
                if let noteStart = verovioService?.getNoteStartTime(noteId) {
                    print("[DEBUG] Seeking to noteStart: \(noteStart) for noteId: \(noteId)")
                    let wasMIDIPlaying = midiPlayer?.isPlaying ?? false
                    midiPlayer?.seek(to: noteStart)
                    if wasMIDIPlaying {
                        midiPlayer?.play()
                    }
                    if let met = metronome {
                        met.seek(to: noteStart)
                        if wasMIDIPlaying && met.isEnabled {
                            met.start()
                        }
                    }
                }
            } else if message.name == "measureClickHandler" {
                print("[DEBUG] measureClickHandler received body: \(message.body)")
                guard let measureId = message.body as? String, !measureId.isEmpty else {
                    print("[DEBUG] measureClickHandler: measureId is nil or empty, aborting"); return
                }
                print("[DEBUG] measureClickHandler received measureId: \(measureId)")
                if let timingMapJSON = verovioService?.getTimingMap().data(using: .utf8),
                   let arr = try? JSONSerialization.jsonObject(with: timingMapJSON) as? [[String: Any]] {
                    if let first = arr.first(where: { entry in
                        if let onArray = entry["on"] as? [String] {
                            return onArray.contains(measureId)
                        }
                        return false
                    }), let tstamp = first["tstamp"] as? Double {
                        let time = tstamp / 1000.0
                        print("[DEBUG] Seeking to tstamp: \(time) for measureId: \(measureId)")
                        let wasPlaying = midiPlayer?.isPlaying ?? false
                        midiPlayer?.seek(to: time)
                        if wasPlaying { midiPlayer?.play() }
                        if let met = metronome { met.seek(to: time); if wasPlaying && met.isEnabled { met.start() } }
                    } else {
                        print("[DEBUG] Could not find timing entry for measureId: \(measureId)")
                    }
                } else {
                    print("[DEBUG] Could not parse timing map JSON for measureId: \(measureId)")
                }
            }
        }
    }

    private func createHTML(svgPages: [String], timingData: String) -> String {
        let svgContent = svgPages.enumerated().map { index, svg in
            let pageLabel = svgPages.count > 1 ? "<div class=\"page-label\">Page \(index + 1)</div>" : ""
            return """
            <div class=\"page\">
                \(pageLabel)
                \(svg)
            </div>
            """
        }.joined(separator: "\n")

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset=\"utf-8\">
            <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
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
                    /* Apply to both filled and stroked musical symbols (notes and rests) */
                    fill: #ff6b6b !important;
                    stroke: #ff6b6b !important;
                    color: #ff6b6b !important;
                    opacity: 0.9;
                }
                /* Dark mode SVG color inversion */
                @media (prefers-color-scheme: dark) {
                  svg {
                    filter: invert(1) hue-rotate(180deg) brightness(1.1) contrast(1.2);
                  }
                  .page-label {
                    color: #aaa;
                  }
                }
            </style>
            <script>
                // Parse Verovio timing data
                const timingData = \(timingData);
                let currentHighlightedElements = [];

                function updatePlaybackHighlight(timeMs) {
                    clearPlaybackHighlight();

                    // Find all notes that should be active at current time
                    if (!timingData || !Array.isArray(timingData)) {
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


                    // Highlight all currently active notes
                    activeNotes.forEach(noteId => {
                        const elements = document.querySelectorAll(`[*|id=\"${noteId}\"]`);
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

                    // Add handlers for all elements that have IDs in our timing data
                    if (timingData && Array.isArray(timingData)) {
                        const allNoteIds = new Set();
                        timingData.forEach(entry => {
                            if (entry.on) {
                                entry.on.forEach(id => allNoteIds.add(id));
                            }
                        });

                        allNoteIds.forEach(noteId => {
                            const elements = document.querySelectorAll(`[*|id=\"${noteId}\"]`);
                            elements.forEach(el => {
                                el.style.cursor = 'pointer';
                                el.addEventListener('click', function(e) {
                                    e.stopPropagation();
                                    window.webkit.messageHandlers.noteClickHandler.postMessage(noteId);
                                });
                            });
                        });

                        // Create clickable overlays for measures
                        const measureGroups = document.querySelectorAll('g.measure, g[class*="measure"], g[id*="measure"], [id^="measure-"]');
                        measureGroups.forEach((g, idx) => {
                            let bbox = null;
                            try { bbox = g.getBBox(); } catch (e) { bbox = null; }
                            if (bbox && bbox.width > 0 && bbox.height > 0) {
                                // Robustly extract measure number from id/class attributes (e.g., 'measure-1', 'measure-P1-3', etc.)
                                let measureNumber = null;
                                try {
                                    const id = g.id || '';
                                    const cls = g.getAttribute && g.getAttribute('class') || '';
                                    // Try to match 'measure-<number>' or 'measure-Px-<number>'
                                    let match = id.match(/measure-(?:[A-Za-z0-9]+-)?(\\d+)/);
                                    if (!match) match = cls.match(/measure-(?:[A-Za-z0-9]+-)?(\\d+)/);
                                    if (match) measureNumber = parseInt(match[1]);
                                    // Fallback: look for <text> child with a number (rare)
                                    if (!measureNumber) {
                                        const texts = g.getElementsByTagName('text');
                                        for (let t of texts) {
                                            const n = parseInt(t.textContent);
                                            if (!isNaN(n)) { measureNumber = n; break; }
                                        }
                                    }
                                    // Final fallback: use overlay index (may be wrong for multi-staff)
                                    if (!measureNumber) measureNumber = idx + 1;
                                } catch(e) { measureNumber = null }
                                const rect = document.createElementNS('http://www.w3.org/2000/svg','rect');
                                rect.setAttribute('x', bbox.x);
                                rect.setAttribute('y', bbox.y);
                                rect.setAttribute('width', bbox.width);
                                rect.setAttribute('height', bbox.height);
                                rect.setAttribute('fill', '#ffe066');
                                rect.setAttribute('opacity', '0.0');
                                rect.style.cursor = 'pointer';
                                rect.addEventListener('click', function(e) {
                                    e.stopPropagation();
                                    // Find all note ids in timingData
                                    const allNoteIds = new Set();
                                    if (timingData && Array.isArray(timingData)) {
                                        timingData.forEach(entry => {
                                            if (entry.on) entry.on.forEach(id => allNoteIds.add(id));
                                        });
                                    }
                                    // Find the first descendant with a matching id
                                    let firstNoteId = null;
                                    for (const id of allNoteIds) {
                                        if (g.querySelector(`[*|id="${id}"]`)) {
                                            firstNoteId = id;
                                            break;
                                        }
                                    }
                                    if (firstNoteId) {
                                        window.webkit.messageHandlers.noteClickHandler.postMessage(firstNoteId);
                                    }
                                });
                                rect.addEventListener('mouseenter', function() { rect.setAttribute('opacity', '0.12'); });
                                rect.addEventListener('mouseleave', function() { rect.setAttribute('opacity', '0.0'); });
                                g.insertBefore(rect, g.firstChild);
                            }
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
    @ObservedObject var metronome: Metronome

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "noteClickHandler")
        config.userContentController.add(context.coordinator, name: "measureClickHandler")
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
        context.coordinator.metronome = metronome

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
        weak var metronome: Metronome?
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "noteClickHandler", let noteId = message.body as? String {

                // Find the start time for this note
                if let noteStart = verovioService?.getNoteStartTime(noteId) {
                    // Map the note start to its containing measure's start time
                    let measureTimings = verovioService?.getMeasureTimings() ?? []

                    // Find the last measure whose time is <= noteStart
                    var measureStartTime: TimeInterval = noteStart
                    if !measureTimings.isEmpty {
                        var chosen: TimeInterval? = nil
                        for entry in measureTimings {
                            let t = entry.time
                            if t <= noteStart {
                                chosen = t
                            } else {
                                break
                            }
                        }
                        if let c = chosen {
                            measureStartTime = c
                        }
                    }

                    // Save state before seek
                    let wasMIDIPlaying = midiPlayer?.isPlaying ?? false
                    midiPlayer?.seek(to: measureStartTime)
                    if wasMIDIPlaying {
                        midiPlayer?.play()
                    }
                    if let met = metronome {
                        met.seek(to: measureStartTime)
                        if wasMIDIPlaying && met.isEnabled {
                            met.start()
                        }
                    }
                }

            } else if message.name == "measureClickHandler" {
                var measureNum: Int? = nil
                if let i = message.body as? Int { measureNum = i }
                else if let d = message.body as? Double { measureNum = Int(d) }
                else if let s = message.body as? String, let i = Int(s) { measureNum = i }

                guard let mNum = measureNum else { return }

                if let measureStart = verovioService?.getMeasureStartTime(mNum) {
                    let wasMIDIPlaying = midiPlayer?.isPlaying ?? false
                    midiPlayer?.seek(to: measureStart)
                    if wasMIDIPlaying { midiPlayer?.play() }
                    if let met = metronome { met.seek(to: measureStart); if wasMIDIPlaying && met.isEnabled { met.start() } }
                } else {
                    if let timingMapJSON = verovioService?.getTimingMap().data(using: .utf8),
                       let arr = try? JSONSerialization.jsonObject(with: timingMapJSON) as? [[String: Any]] {
                        if let first = arr.first(where: { entry in
                            if let measure = entry["measure"] as? Int { return measure == mNum }
                            if let measureStr = entry["measure"] as? String, let mi = Int(measureStr) { return mi == mNum }
                            return false
                        }), let tstamp = first["tstamp"] as? Double {
                            let time = tstamp / 1000.0
                            let wasPlaying = midiPlayer?.isPlaying ?? false
                            midiPlayer?.seek(to: time)
                            if wasPlaying { midiPlayer?.play() }
                            if let met = metronome { met.seek(to: time); if wasPlaying && met.isEnabled { met.start() } }
                        }
                    }
                }
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
                    /* Apply to both filled and stroked musical symbols (notes and rests) */
                    fill: #ff6b6b !important;
                    stroke: #ff6b6b !important;
                    color: #ff6b6b !important;
                    opacity: 0.9;
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
                        // Create clickable overlays for measures
                        const measureGroups = document.querySelectorAll('g.measure, g[class*="measure"], g[id*="measure"], [id^="measure-"]');
                        measureGroups.forEach((g, idx) => {
                            let bbox = null;
                            try { bbox = g.getBBox(); } catch (e) { bbox = null; }
                            if (bbox && bbox.width > 0 && bbox.height > 0) {
                                let measureNumber = null;
                                try {
                                    const id = g.id || '';
                                    const cls = g.getAttribute && g.getAttribute('class') || '';
                                    const combined = id + ' ' + cls;
                                    const match = combined.match(/(\\d+)/);
                                    if (match) measureNumber = parseInt(match[0]);
                                } catch(e) { measureNumber = null }
                                if (!measureNumber) measureNumber = idx + 1;
                                const rect = document.createElementNS('http://www.w3.org/2000/svg','rect');
                                rect.setAttribute('x', bbox.x);
                                rect.setAttribute('y', bbox.y);
                                rect.setAttribute('width', bbox.width);
                                rect.setAttribute('height', bbox.height);
                                rect.setAttribute('fill', '#ffe066');
                                rect.setAttribute('opacity', '0.0');
                                rect.style.cursor = 'pointer';
                                rect.addEventListener('click', function(e) { e.stopPropagation(); window.webkit.messageHandlers.measureClickHandler.postMessage(measureNumber); });
                                rect.addEventListener('mouseenter', function() { rect.setAttribute('opacity', '0.12'); });
                                rect.addEventListener('mouseleave', function() { rect.setAttribute('opacity', '0.0'); });
                                g.insertBefore(rect, g.firstChild);
                            }
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
