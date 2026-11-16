//
//  WhiskyWineDownloadView.swift
//  Whisky
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import SwiftUI

/// Bourbon publishes no Wine runtime to download: it is built from source on this Mac by
/// `Runtime/build.sh`, so this setup step explains how instead of downloading.
struct WhiskyWineDownloadView: View {
    @Binding var tarLocation: URL
    @Binding var path: [SetupStage]

    var body: some View {
        VStack(spacing: 12) {
            Text("setup.whiskywine.download")
                .font(.title)
                .fontWeight(.bold)
            Text(verbatim: "Bourbon's Wine runtime is built from source on this Mac. In the Bourbon repository, "
                 + "run Runtime/build.sh, then reopen Bourbon.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button("setup.quit") {
                exit(0)
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
        .frame(width: 400, height: 200)
    }
}
