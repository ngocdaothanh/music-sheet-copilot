import SwiftUI
import WebKit
// FoundationXML is available on some toolchains as a separate module. Prefer conditional import
#if canImport(FoundationXML)
import FoundationXML
#else
import Foundation
#endif

/// SwiftUI view that displays multiple pages of SVG music notation vertically
struct MultiPageSVGMusicSheetView: View {
    let svgPages: [String]
    let timingData: String
    @ObservedObject var midiPlayer: MIDIPlayer
    @ObservedObject var metronome: Metronome
    // Use explicit current time and playing flag provided by the parent view
    let currentTimeOverride: TimeInterval?
    let isPlayingOverride: Bool?
    @EnvironmentObject var verovioService: VerovioService
    let noteNameMode: NoteNameMode

    var body: some View {
    // Use overrides if provided by parent; otherwise default to MIDI player's values
    let currentTime = currentTimeOverride ?? midiPlayer.currentTime
    let isPlaying = isPlayingOverride ?? midiPlayer.isPlaying

        // Remove outer ScrollView to avoid double scrolling, let WKWebView handle scrolling
        CombinedSVGWebView(svgPages: svgPages, timingData: timingData, currentTime: currentTime, isPlaying: isPlaying, metronome: metronome, noteNameMode: noteNameMode)
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
    let noteNameMode: NoteNameMode

    var body: some View {
        #if os(macOS)
        CombinedSVGWebViewMac(svgPages: svgPages, timingData: timingData, currentTime: currentTime, isPlaying: isPlaying, metronome: metronome, noteNameMode: noteNameMode)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        CombinedSVGWebViewiOS(svgPages: svgPages, timingData: timingData, currentTime: currentTime, isPlaying: isPlaying, metronome: metronome, noteNameMode: noteNameMode)
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
    let noteNameMode: NoteNameMode

    func makeNSView(context: Context) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.userContentController.add(context.coordinator, name: "noteClickHandler")
    config.userContentController.add(context.coordinator, name: "measureClickHandler")
    // Handler for logs coming from the JS side. JS should call the `logToSwiftSide` util (defined in the HTML)
    // instead of console.log so Swift can capture and forward logs to Xcode console.
    config.userContentController.add(context.coordinator, name: "swiftLog")
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
            let annotatedPages = annotateSVGPages(svgPages: svgPages, timingData: timingData, midiEvents: midiPlayer.noteEvents)
            let html = createHTML(svgPages: annotatedPages, timingData: timingData, noteNameMode: noteNameMode.rawValue)
            // Diagnostic logging: print a short snippet and counts of injected attributes so we can confirm annotation
            do {
                let snippet = String(html.prefix(2048))
                let dataMidiCount = html.components(separatedBy: "data-midi=").count - 1
                let dataNoteNameCount = html.components(separatedBy: "data-note-name=").count - 1
                print("[DEBUG] Annotated HTML snippet (first 2KB):\n\(snippet)\n---\n[data-midi] count: \(dataMidiCount), [data-note-name] count: \(dataNoteNameCount)")
            }
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
        // If the note name mode changed since last render, update labels in-place without reloading HTML
        let desiredMode = noteNameMode.rawValue
        if context.coordinator.lastNoteNameMode != desiredMode {
            // Update lastNoteNameMode immediately to avoid duplicate calls
            context.coordinator.lastNoteNameMode = desiredMode
            let script = "try { clearNoteNameLabels(); insertNoteNames('\(desiredMode)'); logAnnotatedElements(); } catch(e) { logToSwiftSide('[update] noteNameMode eval error ' + e); }"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKScriptMessageHandler {
        var currentPages: [String] = []
        var lastNoteNameMode: String? = nil
        weak var verovioService: VerovioService?
        weak var midiPlayer: MIDIPlayer?
        weak var metronome: Metronome?
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "swiftLog" {
                // Print JS logs on the Swift side so they appear in Xcode console.
                // Message body may be a string or other serializable value.
                print("[JS] \(message.body)")
                return
            }
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

    private func createHTML(svgPages: [String], timingData: String, noteNameMode: String) -> String {
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
                // Note name mode forwarded from Swift
                const noteNameMode = "\(noteNameMode)";
                // (logToSwiftSide helper is defined once earlier; avoid duplicate definitions)

                // Insert note name labels above noteheads when requested.
                // Expects parent note elements to have data-note-name or data-midi attributes (injected by Swift annotation).
                function insertNoteNames(mode) {
                    try {
                        if (!mode || mode === 'none') return;
                        // Avoid inserting duplicates by checking for an existing label
                        if (document.querySelectorAll('.note-name-label').length > 0) return;

                        function clientToSVGPoint(svg, clientX, clientY) {
                            try {
                                const pt = svg.createSVGPoint();
                                pt.x = clientX; pt.y = clientY;
                                const ctm = svg.getScreenCTM();
                                if (!ctm) return { x: clientX, y: clientY };
                                const inv = ctm.inverse();
                                const p = pt.matrixTransform(inv);
                                return { x: p.x, y: p.y };
                            } catch (e) { return { x: clientX, y: clientY }; }
                        }

                        // Use the annotated elements directly (elements that Swift injected attributes onto)
                        const annotatedEls = Array.from(document.querySelectorAll('[data-note-name], [data-midi]'));
                        // Minimal logging: report count only
                        logToSwiftSide('[insertNoteNames] annotated elements:', annotatedEls.length);

                        let inserted = 0;
                        annotatedEls.forEach((el, idx) => {
                            try {
                                const anchor = el.closest('g.note') || el;
                                const svg = anchor && (anchor.ownerSVGElement || document.querySelector('svg'));
                                if (!svg) return;

                                // Compute position: place label to the right of the note and align to the bottom of the note.
                                let x = 0, y = 0;
                                try {
                                    // Prefer the actual notehead element inside the group (common patterns: <use>, <ellipse>, <circle>, <path>)
                                    let notehead = null;
                                    let bestBBox = null;
                                    try {
                                        const candidates = anchor.querySelectorAll('use, ellipse, circle, path, rect');
                                        // Score candidates by area and squareness (prefer notehead-like shapes)
                                        let bestScore = -Infinity;
                                        const debugCandidates = [];
                                        candidates.forEach(c => {
                                            try {
                                                const b = c.getBBox();
                                                if (b && b.width > 0 && b.height > 0) {
                                                    const area = b.width * b.height;
                                                    const aspect = b.width / b.height;
                                                    // score: prefer moderate area and aspect ratio near 1 (square/oval)
                                                    const aspectScore = 1 - Math.abs(Math.log(aspect));
                                                    const score = Math.log(area + 1) * aspectScore;
                                                    // also capture client rect if available for more robust placement
                                                    let crect = null;
                                                    try { const r = c.getBoundingClientRect(); crect = {left: r.left, top: r.top, width: r.width, height: r.height}; } catch(e) {}
                                                    debugCandidates.push({ tag: c.tagName, id: c.id || null, bbox: {x: b.x, y: b.y, width: b.width, height: b.height}, clientRect: crect, area: area, aspect: aspect, score: score });
                                                    if (score > bestScore) {
                                                        bestScore = score;
                                                        bestBBox = b;
                                                        notehead = c;
                                                    }
                                                }
                                            } catch (e) { /* ignore bbox errors */ }
                                        });
                                        // Candidate debug logs removed for brevity
                                    } catch(e) { /* ignore query errors */ }

                                    const bb = bestBBox || anchor.getBBox();
                                    // Prefer to compute placement from client bounding rect transformed into SVG coordinates
                                    let placedFromClient = false;
                                    try {
                                        if (notehead && notehead.getBoundingClientRect) {
                                            const cr = notehead.getBoundingClientRect();
                                            const right = cr.left + cr.width;
                                            const pRight = clientToSVGPoint(svg, right + Math.max(6, cr.width * 0.2), cr.top + cr.height / 2);
                                            x = pRight.x;
                                            y = pRight.y;
                                            placedFromClient = true;
                                        }
                                    } catch(e) { placedFromClient = false; }
                                    if (!placedFromClient) {
                                        // Fallback to SVG bbox
                                        const offset = Math.max(6, bb.width * 0.2);
                                        x = bb.x + bb.width + offset;
                                        y = bb.y + bb.height / 2;
                                    }
                                    // Keep minimal placement info
                                    logToSwiftSide('[insertNoteNames] placed element', idx, 'usedClient=', placedFromClient);
                                } catch (e) {
                                    const rect = anchor.getBoundingClientRect ? anchor.getBoundingClientRect() : null;
                                    if (rect) {
                                        const right = rect.left + rect.width;
                                        const p = clientToSVGPoint(svg, right, rect.top + rect.height / 2);
                                        x = p.x + Math.max(6, rect.width * 0.2);
                                        y = p.y;
                                    }
                                }

                                const nameAttr = el.getAttribute('data-note-name') || el.getAttribute('data-midi');
                                if (!nameAttr) return;

                                let label = nameAttr;
                                if (mode === 'letter') {
                                    const m = parseInt(nameAttr);
                                    if (!isNaN(m)) label = ['C','C#','D','D#','E','F','F#','G','G#','A','A#','B'][m % 12];
                                } else if (mode === 'solfege') {
                                    const m = parseInt(nameAttr);
                                    if (!isNaN(m)) label = ['Doh','Doh','Reh','Reh','Mee','Fa','Fa','Sol','Sol','La','La','Si'][m % 12];
                                }

                                const text = document.createElementNS('http://www.w3.org/2000/svg', 'text');
                                text.setAttribute('x', x);
                                text.setAttribute('y', y);
                                text.setAttribute('class', 'note-name-label');
                                // Align label to the right-hand side of the notehead and center vertically on it
                                text.setAttribute('text-anchor', 'start');
                                text.setAttribute('dominant-baseline', 'middle');
                                // Much larger, bold label and explicit font to be readable on most sheet renderings
                                // Scale is now halved from the previous very large size
                                text.setAttribute('font-size', '180');
                                text.setAttribute('font-family', '-apple-system, system-ui, Arial, sans-serif');
                                text.setAttribute('font-weight', '700');
                                // Add a stronger stroke so the label is visible on both light and dark backgrounds
                                // Because the SVG is inverted in dark mode (CSS filter), set pre-inversion colors
                                // so the final displayed colors are: dark mode -> white, light mode -> black.
                                // Setting fill to 'black' here results in black in light mode and (after inversion) white in dark mode.
                                text.setAttribute('fill', 'black');
                                // Use white stroke pre-inversion so it becomes black in dark mode after inversion,
                                // and remains white in light mode to give contrast around black text.
                                text.setAttribute('stroke', 'white');
                                // Stroke sized for current font
                                text.setAttribute('stroke-width', '3');
                                text.setAttribute('paint-order', 'stroke fill');
                                text.style.pointerEvents = 'none';
                                text.textContent = label;
                                // Append label in the correct coordinate space:
                                // - If placedFromClient (we used client->SVG conversion), x/y are in root SVG coords -> append to root svg
                                // - Otherwise append inside anchor so text coordinates are local
                                try {
                                        if (placedFromClient) {
                                        // Create a stable background rect based on font-size and label length (avoid relying on getBBox)
                                        try {
                                            const fs = parseFloat(text.getAttribute('font-size')) || 180;
                                            const charCount = (label || '').length || 1;
                                            const estWidth = Math.max(20, fs * charCount * 0.6);
                                            const estHeight = Math.max(fs * 0.8, fs * 0.8);
                                            const paddingX = Math.max(6, fs * 0.08);
                                            const paddingY = Math.max(3, fs * 0.2);
                                            const rect = document.createElementNS('http://www.w3.org/2000/svg','rect');
                                            // position rect so text (with text-anchor start and dominant-baseline middle) centers vertically
                                            rect.setAttribute('x', x - 2);
                                            rect.setAttribute('y', y - estHeight / 2 - paddingY);
                                            rect.setAttribute('width', estWidth + paddingX * 2);
                                            rect.setAttribute('height', estHeight + paddingY * 2);
                                            rect.setAttribute('rx', String(Math.max(2, fs * 0.06)));
                                            // Use an opaque contrasting background and subtle stroke so background is always visible
                                            rect.setAttribute('fill', isDark ? 'black' : 'white');
                                            rect.setAttribute('stroke', isDark ? 'white' : 'black');
                                            rect.setAttribute('stroke-width', '2');
                                            rect.setAttribute('opacity', isDark ? '0.95' : '1.0');
                                            rect.setAttribute('class', 'note-name-bg');
                                            // Tag with data attribute so clear routine can find any rects created this way
                                            rect.setAttribute('data-note-name-bg', '1');
                                            // Insert rect before text by appending then moving text after to guarantee z-order
                                            svg.appendChild(rect);
                                        } catch (e) { /* ignore */ }
                                        // Append text after rect so it renders on top and tag it for easier clearing
                                        text.setAttribute('data-note-name-label', '1');
                                        svg.appendChild(text);
                                    } else {
                                        if (anchor && anchor.tagName && anchor.tagName.toLowerCase() === 'g') {
                                            anchor.appendChild(text);
                                            try {
                                                const tb = text.getBBox();
                                                const rect = document.createElementNS('http://www.w3.org/2000/svg','rect');
                                                rect.setAttribute('x', tb.x - 8);
                                                rect.setAttribute('y', tb.y - 6);
                                                rect.setAttribute('width', tb.width + 16);
                                                rect.setAttribute('height', tb.height + 12);
                                                rect.setAttribute('rx', '4');
                                                // Use an opaque contrasting background and subtle stroke so background is always visible
                                                rect.setAttribute('fill', isDark ? 'black' : 'white');
                                                rect.setAttribute('stroke', isDark ? 'white' : 'black');
                                                rect.setAttribute('stroke-width', '1.5');
                                                rect.setAttribute('opacity', isDark ? '0.95' : '1.0');
                                                rect.setAttribute('class', 'note-name-bg');
                                                rect.setAttribute('data-note-name-bg', '1');
                                                anchor.insertBefore(rect, text);
                                            } catch (e) { /* ignore */ }
                                        } else {
                                            svg.appendChild(text);
                                        }
                                    }
                                } catch (e) {
                                    if (svg) svg.appendChild(text);
                                }
                                inserted++;
                                } catch (e) {
                                    // Swallow perimeter errors; keep minimal logging
                                }
                        });
                        // Report how many labels were inserted
                        logToSwiftSide('[insertNoteNames] total inserted:', inserted);
                    } catch (e) { /* ignore insertNoteNames errors in production */ }
                }
                function logAnnotatedElements() {
                    try {
                        const annotated = [];
                        // Find elements with data-note-name or data-midi
                        document.querySelectorAll('[data-note-name], [data-midi]').forEach(el => {
                            const id = el.id || el.getAttribute('id') || null;
                            const dn = el.getAttribute('data-note-name');
                            const dm = el.getAttribute('data-midi');
                            annotated.push({ id: id, noteName: dn, midi: dm, tag: el.tagName, cls: el.getAttribute('class') });
                        });
                        // Keep minimal annotated elements count log
                        logToSwiftSide('[logAnnotatedElements] annotatedCount:', annotated.length);
                    } catch(e) { logToSwiftSide('[logAnnotatedElements] error', String(e)); }
                }
                function clearNoteNameLabels() {
                    try {
                        // Remove both class-based elements and any with the data attributes
                        const labels = Array.from(document.querySelectorAll('.note-name-label, [data-note-name-label], [data-note-name-label="1"]'));
                        const bgs = Array.from(document.querySelectorAll('.note-name-bg, [data-note-name-bg], [data-note-name-bg="1"]'));
                        labels.forEach(e => { try { e.remove(); } catch(e) {} });
                        bgs.forEach(e => { try { e.remove(); } catch(e) {} });
                        // Keep a concise removal log
                        logToSwiftSide('[clearNoteNameLabels] removed', labels.length, 'labels,', bgs.length, 'bgs');
                    } catch(e) { logToSwiftSide('[clearNoteNameLabels] error', String(e)); }
                }
                // Utility to forward logs to the Swift side. IMPORTANT: for logging, instead of calling
                // `console.log`, JS should call `logToSwiftSide(...)` so Swift can capture logs in Xcode.
                function logToSwiftSide(...args) {
                    try {
                        const payload = args.map(a => {
                            try { return typeof a === 'string' ? a : JSON.stringify(a); } catch(e) { return String(a); }
                        }).join(' ');
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.swiftLog) {
                            window.webkit.messageHandlers.swiftLog.postMessage(payload);
                        } else {
                            // Fallback to console when not running inside WKWebView
                            console.log.apply(console, args);
                        }
                    } catch(e) {
                        console.log('logToSwiftSide error', e, args);
                    }
                }
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
                    // Signal to Swift that the webview finished loading
                    logToSwiftSide('[load] WebView loaded and handlers set up');

                    // Insert note names if requested
                    try { insertNoteNames(noteNameMode); logAnnotatedElements(); } catch(e) {}

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
                                    logToSwiftSide('[click] note', noteId);
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
                                        timingData.forEach(entry => { if (entry.on) entry.on.forEach(id => allNoteIds.add(id)); });
                                    }
                                    // Find the first descendant with a matching id
                                    let firstNoteId = null;
                                    for (const id of allNoteIds) {
                                        if (g.querySelector(`[*|id="${id}"]`)) { firstNoteId = id; break; }
                                    }
                                    if (firstNoteId) {
                                        logToSwiftSide('[click] measure overlay -> note', firstNoteId);
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
    let noteNameMode: NoteNameMode

    func makeUIView(context: Context) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.userContentController.add(context.coordinator, name: "noteClickHandler")
    config.userContentController.add(context.coordinator, name: "measureClickHandler")
    // Handler for logs coming from the JS side. JS should call the `logToSwiftSide` util (defined in the HTML)
    // instead of console.log so Swift can capture and forward logs to Xcode console.
    config.userContentController.add(context.coordinator, name: "swiftLog")
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
            let annotatedPages = annotateSVGPages(svgPages: svgPages, timingData: timingData, midiEvents: midiPlayer?.noteEvents ?? [])
            let html = createHTML(svgPages: annotatedPages, timingData: timingData, noteNameMode: noteNameMode.rawValue)
            // Diagnostic logging: print a short snippet and counts of injected attributes so we can confirm annotation
            let snippet = String(html.prefix(2048))
            let dataMidiCount = html.components(separatedBy: "data-midi=").count - 1
            let dataNoteNameCount = html.components(separatedBy: "data-note-name=").count - 1
            print("[DEBUG] Annotated HTML snippet (first 2KB):\n\(snippet)\n---\n[data-midi] count: \(dataMidiCount), [data-note-name] count: \(dataNoteNameCount)")
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
        // If the note name mode changed since last render, update labels in-place without reloading HTML
        let desiredMode = noteNameMode.rawValue
        if context.coordinator.lastNoteNameMode != desiredMode {
            context.coordinator.lastNoteNameMode = desiredMode
            let script = "try { clearNoteNameLabels(); insertNoteNames('\(desiredMode)'); logAnnotatedElements(); } catch(e) { console.log('[update] noteNameMode eval error', e); }"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKScriptMessageHandler {
        var currentPages: [String] = []
        var lastNoteNameMode: String? = nil
        weak var verovioService: VerovioService?
        weak var midiPlayer: MIDIPlayer?
        weak var metronome: Metronome?
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "swiftLog" {
                print("[JS] \(message.body)")
                return
            }
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

    private func createHTML(svgPages: [String], timingData: String, noteNameMode: String) -> String {
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
                // Note name mode forwarded from Swift
                const noteNameMode = "\(noteNameMode)";
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
                    logToSwiftSide('[load] WebView loaded and handlers set up');
                    logToSwiftSide('Setting up click handlers for notes');

                    // Insert note names if requested
                    try { insertNoteNames(noteNameMode); logAnnotatedElements(); } catch(e) {}

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
                                    logToSwiftSide('[click] note', noteId);
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
                                rect.addEventListener('click', function(e) { e.stopPropagation(); logToSwiftSide('[click] measure overlay', measureNumber); window.webkit.messageHandlers.measureClickHandler.postMessage(measureNumber); });
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

// MARK: - SVG annotation helper
fileprivate func annotateSVGPages(svgPages: [String], timingData: String, midiEvents: [(time: TimeInterval, midiNote: UInt8, channel: UInt8)]) -> [String] {
    guard let data = timingData.data(using: .utf8),
          let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        return svgPages
    }

    // Build a mapping from element id -> midi note (best-effort)
    var idToMidi: [String: UInt8] = [:]

    // Sort midi events by time
    let sortedMidi = midiEvents.sorted { $0.time < $1.time }

    for entry in arr {
        guard let tstamp = entry["tstamp"] as? Double else { continue }
        let timeSec = tstamp / 1000.0
        if let onArray = entry["on"] as? [String] {
            for id in onArray {
                // find closest midi event
                if let closest = sortedMidi.min(by: { abs($0.time - timeSec) < abs($1.time - timeSec) }), abs(closest.time - timeSec) < 0.15 {
                    idToMidi[id] = closest.midiNote
                }
            }
        }
    }

    func midiToName(_ midi: UInt8) -> String {
        let names = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
        return names[Int(midi) % 12]
    }

    var result: [String] = []
    for svg in svgPages {
        // Try robust XML-based injection first. If parsing fails, fall back to string replacement.
        if let data = svg.data(using: .utf8) {
            do {
                let xmlDoc = try XMLDocument(data: data, options: .nodePreserveAll)

                for (id, midi) in idToMidi {
                    let noteName = midiToName(midi)
                    // Use XPath to find any element with matching id attribute
                    let xpath = "//*[@id='\(id)']"
                    if let nodes = try xmlDoc.nodes(forXPath: xpath) as? [XMLNode], !nodes.isEmpty {
                        for node in nodes {
                            if let element = node as? XMLElement {
                                element.addAttribute(XMLNode.attribute(withName: "data-midi", stringValue: "\(midi)") as! XMLNode)
                                element.addAttribute(XMLNode.attribute(withName: "data-note-name", stringValue: noteName) as! XMLNode)
                            }
                        }
                    } else {
                        // No nodes found for this id in the parsed XML; continue — we may fall back later
                    }
                }

                // Export annotated XML back to string
                let annotated = xmlDoc.xmlString(options: .nodePreserveAll)
                result.append(annotated)
                continue
            } catch {
                // Parsing failed; will perform string replacement fallback below
            }
        }

        // Fallback: best-effort string replacement (previous behavior)
        var annotated = svg
        for (id, midi) in idToMidi {
            let search = "id=\"\(id)\""
            if annotated.contains(search) {
                let noteName = midiToName(midi)
                let replacement = "id=\"\(id)\" data-midi=\"\(midi)\" data-note-name=\"\(noteName)\""
                annotated = annotated.replacingOccurrences(of: search, with: replacement)
            }
        }
        result.append(annotated)
    }

    return result
}
