//
//  ContentView.swift
//  MusicSheetsCopilot
//
//  Created on November 4, 2025.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var musicScore: MusicScore?
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack {
            if let score = musicScore {
                MusicSheetView(score: score)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)

                    Text("Music Sheets")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Load a MusicXML file or try the demo")
                        .foregroundColor(.secondary)

                    HStack(spacing: 15) {
                        Button("Load Demo") {
                            loadDemoFile()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Open File...") {
                            isImporting = true
                        }
                        .buttonStyle(.bordered)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .padding()
                    }
                }
                .padding()
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.xml, UTType(filenameExtension: "musicxml") ?? .xml],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openDocument)) { _ in
            isImporting = true
        }
        .navigationTitle(musicScore?.title ?? "Music Sheets")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup {
                if musicScore != nil {
                    Button("Load Another") {
                        isImporting = true
                    }

                    Button("Demo") {
                        loadDemoFile()
                    }
                }
            }
        }
    }

    private func loadDemoFile() {
        guard let url = Bundle.main.url(forResource: "twinkle_twinkle", withExtension: "xml") else {
            errorMessage = "Demo file not found"
            return
        }

        loadMusicXML(from: url)
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            loadMusicXML(from: url)
        case .failure(let error):
            errorMessage = "Failed to open file: \(error.localizedDescription)"
        }
    }

    private func loadMusicXML(from url: URL) {
        errorMessage = nil

        do {
            let data = try Data(contentsOf: url)
            let parser = MusicXMLParser()
            musicScore = try parser.parse(data: data)
        } catch {
            errorMessage = "Failed to parse MusicXML: \(error.localizedDescription)"
            musicScore = nil
        }
    }
}

#Preview {
    NavigationStack {
        ContentView()
    }
}
