import DesignSystem
import PyodideSpike
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
  import AppKit
#elseif os(iOS)
  import UIKit
#endif

/// Explicit development entry point for both native apps. Constructing or presenting this view
/// creates no folder, interpreter, network request or background task. Start is always explicit.
struct PyodideReviewView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @State private var model = PyodideReviewModel()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DS.Space.s6) {
        PyodideReviewBoundary()
        PyodideReviewInterpreter(model: model)
        PyodideReviewWorkloads(model: model)
        PyodideReviewBackground(model: model)
        if let startup = model.startup { PyodideReviewStartup(startup: startup) }
        if let presentation = model.presentation { PyodideReviewResultView(result: presentation) }
        PyodideReviewEvidenceView(model: model)
        PyodideReviewLimitations()
      }
      .frame(maxWidth: DS.Layout.Card.maxWidth, alignment: .leading)
      .padding(DS.Space.s6)
      .frame(maxWidth: .infinity)
    }
    .background(DS.Colors.Surface.window)
    .foregroundStyle(DS.Colors.Text.primary)
    .navigationTitle("Python S6 Review")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Close Review") {
          model.close()
          dismiss()
        }
      }
    }
    .onAppear { model.sceneChanged(scenePhase, isTransition: false) }
    .onChange(of: scenePhase) { _, phase in model.sceneChanged(phase) }
    .onDisappear { model.close() }
    #if os(iOS)
      .onReceive(
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
      ) { _ in
        model.receivedMemoryPressure()
      }
    #endif
    .accessibilityIdentifier("pyodideReview")
  }
}

private struct PyodideReviewBoundary: View {
  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s3) {
      Label("Native S6 Measurement", systemImage: "testtube.2")
        .font(DS.Typography.title1)
        .accessibilityAddTraits(.isHeader)
      Text("Development review · not an S6 gate verdict")
        .font(DS.Typography.headline)
      Text(
        "Runs the real bundled offline interpreter in a hidden, nonpersistent WebKit realm. No production Python tool, network, gateway, remote-Mac fallback or user-folder access is enabled."
      )
      .font(DS.Typography.callout)
      .foregroundStyle(DS.Colors.Text.secondary)
    }
  }
}

private struct PyodideReviewInterpreter: View {
  let model: PyodideReviewModel

  var body: some View {
    DesignCard("Interpreter") {
      LabeledContent("Actual host state") {
        Text(verbatim: PyodideReviewModel.stateCode(model.hostState))
          .font(DS.Typography.callout.monospaced())
          .textSelection(.enabled)
      }
      Text(model.status).accessibilityIdentifier("pyodideReview.status")
      if model.isBusy {
        ProgressView("Measurement in progress")
          .accessibilityIdentifier("pyodideReview.running")
      }
      if let date = model.cellStartedAt {
        HStack {
          Text("Time since the bridge reported code execution:")
          Text(date, style: .timer).monospacedDigit()
        }
        .font(DS.Typography.callout)
      }
      if let failure = model.failure {
        Label {
          Text(verbatim: failure.localizedSummary)
        } icon: {
          Image(systemName: "exclamationmark.triangle")
        }
        .foregroundStyle(DS.Colors.Status.Danger.fg)
        .accessibilityIdentifier("pyodideReview.failure")
        Text(verbatim: failure.rawValue).font(DS.Typography.callout.monospaced())
      }
      if let problem = model.evidenceProblem {
        Label {
          Text(problem)
        } icon: {
          Image(systemName: "externaldrive.badge.exclamationmark")
        }
        .foregroundStyle(DS.Colors.Status.Danger.fg)
      }
      // One view tree for the row and the column, unlike ViewThatFits's two copies.
      DesignFittingStack(spacing: DS.Space.s3) {
        PyodideReviewStartButton(model: model)
        PyodideReviewStopButton(model: model)
        Button("Close Interpreter") { model.close() }.disabled(!model.canClose)
      }
      .buttonStyle(.bordered)
      Text(
        "Start creates a new canonical 0700 review directory only when needed. Stop, timeout, memory pressure and Close discard the realm. Restart is explicit; saved files are never deleted."
      )
      .font(DS.Typography.callout)
      .foregroundStyle(DS.Colors.Text.secondary)
    }
  }
}

private struct PyodideReviewStartButton: View {
  let model: PyodideReviewModel
  var body: some View {
    Button("Start / Recreate Interpreter", systemImage: "play.fill") { model.start() }
      .disabled(!model.canStart)
      .accessibilityIdentifier("pyodideReview.start")
  }
}

private struct PyodideReviewStopButton: View {
  let model: PyodideReviewModel
  var body: some View {
    Button("Stop & Discard Realm", systemImage: DS.Icons.Composer.stop, role: .destructive) {
      model.cancel()
    }
    .disabled(!model.canCancel)
    .accessibilityIdentifier("pyodideReview.stop")
  }
}

private struct PyodideReviewWorkloads: View {
  let model: PyodideReviewModel
  @State private var bridgeCount = 1
  @State private var pandasRuns = 1
  @State private var confirmsPandas = false

  var body: some View {
    DesignCard("Workloads & Interruption Probes") {
      Text(
        "The scientific workload stages a genuine CSV in this session's private folder, reads it with pandas, uses NumPy and SciPy, returns a native table and Matplotlib Agg PNG, then exports a new result.csv."
      )
      .font(.callout)
      Picker("Scientific bridge calls", selection: $bridgeCount) {
        Text("1 call").tag(1)
        Text("20 calls").tag(20)
      }
      .pickerStyle(.segmented)
      .disabled(model.isBusy || model.waitingForContinuedTask)
      Button("Run Scientific Bridge", systemImage: "chart.xyaxis.line") {
        model.runBridge(count: bridgeCount)
      }
      .disabled(!model.canRun)
      .accessibilityIdentifier("pyodideReview.bridge")
      if model.bridgeRequested > 0 {
        Text("Scientific returns saved: \(model.bridgeCompleted) of \(model.bridgeRequested)")
          .font(DS.Typography.callout.monospacedDigit())
      }
      Divider()
      Button("Probe Timeout (0.5-second deadline)", systemImage: "timer") { model.runTimeout() }
        .disabled(!model.canRun)
        .accessibilityIdentifier("pyodideReview.timeout")
      Button("Probe Cancellation After Code Starts", systemImage: "stop.circle") {
        model.runCancellation()
      }
      .disabled(!model.canRun)
      .accessibilityIdentifier("pyodideReview.cancellation")
      Text(
        "Both probes run a real infinite Python cell. Success means the expected error was observed and the realm discarded, not that the cell finished."
      )
      .font(DS.Typography.callout)
      .foregroundStyle(DS.Colors.Text.secondary)
      Divider()
      Picker("Million-row pandas memory workload", selection: $pandasRuns) {
        Text("1 × 10 minutes").tag(1)
        Text("5 × 10 minutes").tag(5)
      }
      .disabled(model.isBusy || model.waitingForContinuedTask)
      Button("Choose Long Pandas Measurement…", systemImage: "memorychip") { confirmsPandas = true }
        .disabled(!model.canRun)
        .accessibilityIdentifier("pyodideReview.pandas")
      Text(
        "The five-run choice is the existing S6.2 workload. Attach Instruments to this session's WebContent process; app RSS is not WebContent peak physical footprint."
      )
      .font(DS.Typography.callout)
      .foregroundStyle(DS.Colors.Text.secondary)
    }
    .buttonStyle(.bordered)
    .confirmationDialog(
      "Run the long pandas measurement?", isPresented: $confirmsPandas, titleVisibility: .visible
    ) {
      Button("Run \(pandasRuns) ten-minute cells") { model.runPandas(runs: pandasRuns) }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "Each cell repeatedly groups and rolls a real million-row pandas frame for 600 seconds. This can consume substantial memory, battery and time. Stop discards the interpreter; there is no automatic retry."
      )
    }
  }
}

private struct PyodideReviewBackground: View {
  let model: PyodideReviewModel

  var body: some View {
    DesignCard("Background Lifecycle Probe") {
      Text(
        "Start a 60-second pandas cell, send the app to the background, then return. Scene callbacks and the real result or error are saved. A process kill may deliver no callback and leaves an unknown outcome; this view does not resume or retry it."
      )
      .font(.callout)
      Button("Begin Without Continued Processing", systemImage: "rectangle.on.rectangle") {
        model.runBackground()
      }
      .disabled(!model.canRun)
      .accessibilityIdentifier("pyodideReview.background")
      #if os(iOS)
        Button("Request Continued-Processing Measurement", systemImage: "clock.arrow.circlepath") {
          model.requestContinuedBackground()
        }
        .disabled(!model.canRun)
        .accessibilityIdentifier("pyodideReview.continued")
        Text(model.continuedStatus).font(DS.Typography.callout)
        Text(
          "Submission is not a grant. The continued workload starts only in a real BGContinuedProcessingTask launch callback. Expiration or system-UI cancellation tears down Python before ending the task."
        )
        .font(DS.Typography.callout)
        .foregroundStyle(DS.Colors.Text.secondary)
      #else
        Text(
          "BGContinuedProcessingTask is an iPhone/iPad framework path, not a Mac measurement. Mac observations cannot pass the reference-iPhone background gate."
        )
        .font(DS.Typography.callout)
        .foregroundStyle(DS.Colors.Text.secondary)
      #endif
    }
    .buttonStyle(.bordered)
  }
}

private struct PyodideReviewStartup: View {
  let startup: PyodideStartup

  var body: some View {
    DesignCard("Actual Verified Startup & Payload") {
      LabeledContent("Pyodide payload", value: startup.pyodideVersion)
      LabeledContent("Core ready (seconds)") {
        Text(startup.coreSeconds, format: .number.precision(.fractionLength(3)))
      }
      LabeledContent("Scientific imports (seconds)") {
        Text(startup.scientificStackSeconds, format: .number.precision(.fractionLength(3)))
      }
      LabeledContent("Web view to ready (seconds)") {
        Text(startup.webViewToReadySeconds, format: .number.precision(.fractionLength(3)))
      }
      LabeledContent("Pinned payload bytes", value: startup.bundledBytes.formatted())
      Text("Bundled bytes are not an app download or installed-size delta.")
        .font(DS.Typography.callout)
        .foregroundStyle(DS.Colors.Text.secondary)
      ForEach(startup.packageVersions.keys.sorted(), id: \.self) { name in
        LabeledContent(name, value: startup.packageVersions[name] ?? "")
          .font(DS.Typography.callout.monospaced())
      }
      LabeledContent(
        "Native transport supplied",
        value: startup.networkConfigured
          ? String(localized: "Yes") : String(localized: "No · offline host"))
      LabeledContent(
        "Detected Lockdown Mode",
        value: startup.lockdownEnabled
          ? String(localized: "Enabled") : String(localized: "Not enabled for this startup"))
      Text(
        "Versions and times above come from the validated host startup, never a canned measurement. A supplied native transport proves neither a grant nor complete network confinement. Enabled Lockdown Mode fails closed instead of silently using another runtime."
      )
      .font(DS.Typography.callout)
      .foregroundStyle(DS.Colors.Text.secondary)
    }
  }
}

private struct PyodideReviewEvidenceView: View {
  let model: PyodideReviewModel
  @State private var exporting: PyodideReviewFile?
  @State private var isExporting = false

  var body: some View {
    DesignCard("Saved Evidence") {
      if let report = model.report {
        LabeledContent("Evidence class") { Text(verbatim: report.environment.evidenceClass) }
        LabeledContent("Machine", value: report.environment.machine)
        LabeledContent("Operating system", value: report.environment.os)
        LabeledContent("App PID", value: report.environment.processID.formatted())
        LabeledContent("Driver observations", value: report.observations.count.formatted())
        if let latest = report.observations.last {
          Text(verbatim: latest.scenario).font(DS.Typography.callout.monospaced())
          LabeledContent("Latest observation (seconds)") {
            Text(latest.seconds, format: .number.precision(.fractionLength(3)))
          }
          if let failure = latest.failure {
            Text("Recorded probe/error code: \(failure.rawValue)").font(DS.Typography.callout)
          }
        }
      }
      if let directory = model.directory {
        Text("Private session directory (retained, never deleted here)").font(DS.Typography.callout)
        Text(verbatim: directory.path)
          .font(DS.Typography.callout.monospaced())
          .textSelection(.enabled)
          .accessibilityIdentifier("pyodideReview.directory")
        #if os(macOS)
          Button("Reveal Saved Evidence in Finder", systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([directory])
          }
        #endif
      }
      Button("Save Current Report Snapshot", systemImage: "square.and.arrow.down") {
        model.saveSnapshot()
      }
      .disabled(model.directory == nil)
      .accessibilityIdentifier("pyodideReview.saveReport")
      if let snapshot = model.latestSnapshot {
        Button("Export Latest Report…", systemImage: "square.and.arrow.up") {
          exporting = snapshot
          isExporting = true
        }
        .accessibilityIdentifier("pyodideReview.exportReport")
      }
      Text(
        "Reports are genuine content-free driver/native metadata. Scientific result JSON contains actual stdout, table values and PNG data; PNG and CSV files are also saved individually. Save or share deliberately. Exports do not assert physical/reference acceptance."
      )
      .font(DS.Typography.callout)
      .foregroundStyle(DS.Colors.Text.secondary)
      DisclosureGroup("Saved files (bounded to 200 indexed entries)") {
        ForEach(model.files.reversed()) { file in
          PyodideReviewFileRow(file: file) {
            exporting = file
            isExporting = true
          }
        }
        if model.omittedFileEntries > 0 {
          Text(
            "\(model.omittedFileEntries) older entries are outside the bounded in-memory index; the files remain in their private session directory."
          )
          .font(DS.Typography.callout)
        }
      }
      DisclosureGroup("Recent native events (up to 12)") {
        ForEach(model.events.suffix(12)) { event in
          VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(verbatim: event.event).font(DS.Typography.callout.monospaced())
            Text(event.at, format: .dateTime.hour().minute().second()).font(DS.Typography.callout)
            if let detail = event.detail {
              Text(verbatim: detail).font(DS.Typography.callout.monospaced())
            }
          }
          .textSelection(.enabled)
        }
        if model.omittedEvents > 0 {
          Text("Older native events omitted from the bounded event index: \(model.omittedEvents)")
            .font(DS.Typography.callout)
        }
      }
    }
    .buttonStyle(.bordered)
    .fileExporter(
      isPresented: $isExporting, item: exporting,
      contentTypes: [exporting?.contentType ?? .data], defaultFilename: exporting?.name
    ) { result in
      model.exportFinished(result)
      exporting = nil
    } onCancellation: {
      exporting = nil
    }
  }
}

private struct PyodideReviewFileRow: View {
  let file: PyodideReviewFile
  let export: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s2) {
      Text(verbatim: file.path).font(DS.Typography.callout.monospaced()).textSelection(.enabled)
      Text("\(file.bytes) bytes · SHA-256 \(file.sha256)")
        .font(DS.Typography.callout.monospaced())
        .textSelection(.enabled)
      HStack(spacing: DS.Space.s3) {
        Button("Save File…", action: export)
        ShareLink(item: file, preview: SharePreview(file.name)) {
          Label("Share File", systemImage: "square.and.arrow.up")
        }
      }
      Divider()
    }
    .padding(.vertical, DS.Space.s2)
  }
}

private struct PyodideReviewLimitations: View {
  var body: some View {
    DesignCard("Not Measured by This View") {
      Text(
        "Reference acceptance needs the physical iPhone 14 Pro and matching OS/build/payload. Collect at least 20 separate app-launch samples for cold p95; recreating a realm in one app launch is not cold-start evidence."
      )
      Text(
        "Attribute Instruments peak physical footprint to WebContent, and collect device jetsam logs. A WebKit termination callback alone never proves jetsam. Measure download/install delta against the same build without the payload."
      )
      Text(
        "Physical Lockdown Mode, real device background suspension/expiration, app-switcher kill behavior and external gateway/no-bypass packet capture remain separate observations. This offline surface does not run a network canary or register an engine/model tool."
      )
    }
    .font(DS.Typography.callout)
    .foregroundStyle(DS.Colors.Text.secondary)
  }
}

@MainActor
struct PyodideReviewResultPresentation {
  struct Cell: Identifiable {
    let id: String
    let text: String
  }
  struct Row: Identifiable {
    let id: String
    let cells: [Cell]
  }
  struct NativeTable: Identifiable {
    let id: String
    let columns: [Cell]
    let rows: [Row]
    let totalRows: Int
    let decoded: Bool
  }
  struct Figure: Identifiable {
    let id: String
    let image: Image?
  }

  let requestID: UUID
  let seconds: Double
  let stdout: String
  let stderr: String
  let textTruncated: Bool
  let tables: [NativeTable]
  let figures: [Figure]

  init(result: PyodideResult) {
    requestID = result.requestID
    seconds = result.elapsedSeconds
    stdout = String(result.stdout.prefix(8_192))
    stderr = String(result.stderr.prefix(8_192))
    textTruncated = stdout.count != result.stdout.count || stderr.count != result.stderr.count
    tables = result.tables.enumerated().map { index, table in
      let id = "\(result.requestID)-table-\(index)"
      let columns = table.columns.enumerated().map {
        Cell(id: "\(id)-column-\($0.offset)", text: $0.element)
      }
      let decoded = (try? JSONSerialization.jsonObject(with: Data(table.jsonRows.utf8))) as? [[Any]]
      let rows = (decoded ?? []).prefix(100).enumerated().map { rowIndex, values in
        Row(
          id: "\(id)-row-\(rowIndex)",
          cells: values.enumerated().map { columnIndex, value in
            Cell(id: "\(id)-row-\(rowIndex)-column-\(columnIndex)", text: Self.cellText(value))
          })
      }
      return NativeTable(
        id: id, columns: columns, rows: rows, totalRows: table.totalRows, decoded: decoded != nil)
    }
    figures = result.figures.enumerated().map { index, figure in
      let image: Image?
      #if os(macOS)
        image = NSImage(data: figure.png).map { Image(nsImage: $0) }
      #elseif os(iOS)
        image = UIImage(data: figure.png).map { Image(uiImage: $0) }
      #endif
      return Figure(id: "\(result.requestID)-figure-\(index)", image: image)
    }
  }

  private static func cellText(_ value: Any) -> String {
    if value is NSNull { return "null" }
    if let text = value as? String { return String(text.prefix(512)) }
    if let value = value as? NSNumber { return value.stringValue }
    guard
      let data = try? JSONSerialization.data(
        withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
    else {
      return String(localized: "Value could not be displayed; inspect the saved result JSON.")
    }
    return String(String(decoding: data, as: UTF8.self).prefix(512))
  }
}

private struct PyodideReviewResultView: View {
  let result: PyodideReviewResultPresentation

  var body: some View {
    DesignCard("Latest Saved Scientific Return") {
      Text(verbatim: result.requestID.uuidString.lowercased()).font(
        DS.Typography.callout.monospaced())
      LabeledContent("Host call (seconds)") {
        Text(result.seconds, format: .number.precision(.fractionLength(3)))
      }
      if !result.stdout.isEmpty {
        Text(verbatim: result.stdout).font(.callout.monospaced()).textSelection(.enabled)
      }
      if !result.stderr.isEmpty {
        Text(verbatim: result.stderr).font(DS.Typography.callout.monospaced()).textSelection(
          .enabled)
      }
      if result.textTruncated {
        Text("Text preview is bounded. The saved result JSON retains the full returned text.").font(
          DS.Typography.callout)
      }
      ForEach(result.tables) { table in PyodideReviewNativeTable(table: table) }
      ForEach(result.figures) { figure in
        if let image = figure.image {
          image.resizable().scaledToFit()
            .accessibilityLabel("Actual Matplotlib Agg PNG returned by the scientific cell")
        } else {
          Text("The returned PNG could not be decoded for display. Inspect its genuine saved file.")
            .font(DS.Typography.callout)
        }
      }
    }
    .accessibilityIdentifier("pyodideReview.result")
  }
}

private struct PyodideReviewNativeTable: View {
  let table: PyodideReviewResultPresentation.NativeTable

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s2) {
      Text("Native table · \(table.totalRows) total rows · \(table.rows.count) displayed")
        .font(DS.Typography.callout)
      if table.decoded {
        ScrollView(.horizontal) {
          Grid(alignment: .leading, horizontalSpacing: DS.Space.s5, verticalSpacing: DS.Space.s2) {
            GridRow {
              ForEach(table.columns) { column in
                Text(verbatim: column.text).font(DS.Typography.callout.weight(.semibold))
              }
            }
            ForEach(table.rows) { row in
              GridRow {
                ForEach(row.cells) { cell in
                  Text(verbatim: cell.text).font(DS.Typography.callout.monospaced()).textSelection(
                    .enabled)
                }
              }
            }
          }
          .padding(DS.Space.s3)
        }
      } else {
        Text("The returned table JSON could not be displayed. Inspect the saved result JSON.")
          .font(DS.Typography.callout)
      }
    }
  }
}

extension PyodideFailure {
  /// The failure summary in the person's language. `errorDescription` stays English: the
  /// development Python tool returns it to the model.
  fileprivate var localizedSummary: String {
    switch self {
    case .bundleMissing:
      String(
        localized: "The pinned offline Python payload is missing. Package it before running S6.")
    case .bundleIntegrity:
      String(localized: "The bundled Python payload did not match its pinned manifest.")
    case .invalidRequest:
      String(localized: "The Python request exceeds the spike's declared limits.")
    case .unsafePath:
      String(localized: "A Python file path or linked filesystem object was refused.")
    case .fileUnavailable:
      String(localized: "A declared Python input or output file is unavailable.")
    case .fileChanged:
      String(localized: "A Python input changed while it was being copied. Nothing ran.")
    case .outputConflict:
      String(localized: "A Python output would replace an existing file. Nothing was replaced.")
    case .outputLimit:
      String(localized: "Python output exceeded the spike's bounded result size.")
    case .busy: String(localized: "This bot already has a Python call in flight.")
    case .notReady: String(localized: "This bot's Python interpreter is not ready.")
    case .startupFailed: String(localized: "The offline Python interpreter could not start.")
    case .startTimedOut:
      String(
        localized:
          "Python could not start within its start limit, so the cell did not run and nothing ran. Its interpreter was discarded; the call may be retried."
      )
    case .scriptFailed: String(localized: "The Python cell failed. No output files were exported.")
    case .cancelled:
      String(
        localized: "Python was stopped; its web view and in-memory interpreter were discarded.")
    case .timedOut:
      String(localized: "Python reached its wall-time limit; its interpreter was discarded.")
    case .webContentTerminated:
      String(localized: "WebKit terminated Python's content process. The cell was not retried.")
    case .hostClosed: String(localized: "The Python host was closed.")
    case .lockdownRequiresMac:
      String(localized: "Lockdown Mode is enabled. Python needs an available, authorized Mac.")
    case .packageUnavailable:
      String(
        localized: "That package is not in the pinned offline stack. No package was downloaded.")
    case .backgroundInterrupted:
      String(localized: "Python was stopped because the app could not keep this run active.")
    case .networkFailed: String(localized: "The Python network request failed.")
    case .idleExpired:
      String(
        localized:
          "Python was idle past its limit, so its interpreter was discarded. Start it again to continue."
      )
    case .lifetimeExpired:
      String(
        localized:
          "Python reached its session lifetime, so its interpreter was discarded. Start it again to continue."
      )
    }
  }
}
