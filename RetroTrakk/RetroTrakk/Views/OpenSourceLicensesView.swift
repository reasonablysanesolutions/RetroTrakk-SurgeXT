// RetroTrakk — OpenSourceLicensesView.swift
// Visar licenser för bundlade resurser (MuseScore General, FluidR3 m.fl.)
// Nås via RetroTrakk -> About -> Open Source Licenses.

import SwiftUI

struct OpenSourceLicensesView: View {
    @Environment(\.dismiss) var dismiss

    private var licenseText: String {
        if let url = Bundle.main.url(forResource: "MuseScore_General_License", withExtension: "md", subdirectory: "Licenses") ??
                     Bundle.main.url(forResource: "MuseScore_General_License", withExtension: "md") {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                return text
            }
        }
        let devPaths = [
            "RetroTrakk/RetroTrakk/Resources/Licenses/MuseScore_General_License.md",
            "RetroTrakk/Resources/Licenses/MuseScore_General_License.md",
            "Resources/Licenses/MuseScore_General_License.md"
        ]
        for path in devPaths {
            if let text = try? String(contentsOfFile: path, encoding: .utf8) {
                return text
            }
        }
        return """
        # MuseScore_General.sf2
        Current version: 0.2 (13th May 2020)

        FluidR3 (original version) by Frank Wen Copyright (c) 2000-02
        Mono conversion (FluidR3Mono) by Michael Cowgill Copyright (c) 2014-17
        Adaptation for MuseScore_General.sf2 by S. Christian Collins Copyright (c) 2018-19
        Temple Blocks instrument provided by Ethan Winer Copyright (c) 2002
        Drumline Cymbals provided by Michael Schorsch Copyright (c) 2016

        Shared under the MIT license:

        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software and associated documentation files (the "Software"), to deal
        in the Software without restriction, including without limitation the rights
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
        copies of the Software, and to permit persons to whom the Software is
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in
        all copies or substantial portions of the Software.
        """
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open Source Licenses")
                        .font(.title2).bold()
                    Text("Licensinformation och upphovsrätt för bundlade ljudresurser i RetroTrakk")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Stäng") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 4)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(licenseText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                }
                .padding(.vertical, 4)
            }
        }
        .padding(20)
        .frame(minWidth: 580, minHeight: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
