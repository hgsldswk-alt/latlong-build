import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import XCTest

final class CoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let coordinate = Coordinate(latitude: 35.713842, longitude: 139.772461)

    private func fix(accuracy: Double = 20, age: TimeInterval = 0, reduced: Bool = false) -> Fix {
        Fix(coordinate: coordinate, accuracy: accuracy, time: now.addingTimeInterval(-age), reduced: reduced)
    }

    func testDecimalAndDMSSignsCarryAndBoundaries() {
        XCTAssertEqual(CoordinateFormat.dd.text(-0.0, latitude: true), "0.000000")
        XCTAssertEqual(CoordinateFormat.dd.text(-180, latitude: false), "-180.000000")
        XCTAssertEqual(CoordinateFormat.dd.text(90, latitude: true), "90.000000")
        XCTAssertEqual(CoordinateFormat.dms.text(-89.999999, latitude: true), "90° 0′ 0.0″ " + L.t("hemisphere.south"))
        XCTAssertEqual(CoordinateFormat.dms.text(179.999999, latitude: false), "180° 0′ 0.0″ " + L.t("hemisphere.east"))
        XCTAssertTrue(Coordinate(latitude: -90, longitude: -180).isValid)
        XCTAssertFalse(Coordinate(latitude: 90.001, longitude: 0).isValid)
        XCTAssertFalse(Coordinate(latitude: 0, longitude: .nan).isValid)
        XCTAssertNotEqual(L.t("app.name"), "app.name")
    }

    func testFixFreshnessAndAccuracy() {
        XCTAssertTrue(fix(age: 10).isUsable(at: now))
        XCTAssertFalse(fix(age: 10.01).isUsable(at: now))
        XCTAssertFalse(fix(age: -2.01).isUsable(at: now))
        XCTAssertFalse(fix(accuracy: -1).isUsable(at: now))
        XCTAssertFalse(fix(accuracy: .infinity).isUsable(at: now))
        XCTAssertEqual(fix().quality, .good)
        XCTAssertEqual(fix(accuracy: 20.01).quality, .low)
        XCTAssertEqual(fix(accuracy: 5, reduced: true).quality, .low)
    }

    func testAtomicStoreRecoveryAndExportAfterExpiry() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("waypoints.json")
        let store = WaypointStore(file: url)
        let created = try await store.createProject("Field")
        let project = try XCTUnwrap(created.activeProjectID)
        let (_, first) = try await store.save(fix(), now: now, projectID: project, pro: true)
        do {
            _ = try await store.save(fix(), now: now.addingTimeInterval(0.2), projectID: project, pro: true)
            XCTFail("A rapid repeated save should be rejected")
        } catch { XCTAssertEqual(error as? LibraryError, .duplicate) }
        let (_, second) = try await store.save(fix(), now: now.addingTimeInterval(1), projectID: project, pro: false)
        XCTAssertNil(second.projectID)
        XCTAssertFalse(second.legacyExport)
        let reopened = WaypointStore(file: url)
        let stored = try await reopened.load()
        XCTAssertEqual(stored.points.map(\.seq), [1, 2])
        let snapshot = stored.export(for: project, filter: PointFilter(quality: .good), pro: false)
        XCTAssertEqual(snapshot.points.map(\.id), [first.id])
        XCTAssertTrue(stored.export(for: nil, filter: PointFilter(), pro: false).points.isEmpty)
        _ = try await reopened.deletePoint(first.id)
        XCTAssertEqual(snapshot.points.map(\.id), [first.id])
        let (_, next) = try await reopened.save(fix(), now: now.addingTimeInterval(3), projectID: project, pro: true)
        XCTAssertEqual(next.seq, 3)
    }

    func testConcurrentMutationsKeepUniqueSequences() async throws {
        let store = WaypointStore(file: nil)
        let date = now
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<12 {
                group.addTask {
                    let value = Fix(coordinate: Coordinate(latitude: Double(index), longitude: 20),
                                    accuracy: 3, time: date, reduced: false)
                    _ = try await store.save(value, now: date, projectID: nil, pro: true)
                }
            }
            try await group.waitForAll()
        }
        let value = try await store.load()
        XCTAssertEqual(value.points.map(\.seq), Array(1...12))
        XCTAssertEqual(value.milestones.deviceCount, 12)
    }

    func testCorruptStoreIsNotOverwritten() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("waypoints.json")
        let original = Data("not a valid library".utf8)
        try original.write(to: url)
        let store = WaypointStore(file: url)
        do {
            _ = try await store.save(fix(), now: now, projectID: nil, pro: true)
            XCTFail("Corrupt libraries should be preserved")
        } catch { XCTAssertEqual(try Data(contentsOf: url), original) }
    }

    func testCodeRoundTripValidationAndDuplicateImport() async throws {
        let source = ShareCode(coordinate: coordinate, name: "集合場所", accuracy: 86, quality: .low)
        let encoded = try source.encode()
        XCTAssertTrue(encoded.hasPrefix("LL1:"))
        XCTAssertFalse(encoded.contains("="))
        XCTAssertEqual(try ShareCode.decode("\n" + encoded + "\n"), source)
        XCTAssertThrowsError(try ShareCode.decode("LL2:" + String(encoded.dropFirst(4))))
        XCTAssertThrowsError(try ShareCode.decode(encoded + String(repeating: " ", count: 1024)))
        XCTAssertThrowsError(try ShareCode.decode("LL1:ABC="))
        let invalid = ShareCode(coordinate: Coordinate(latitude: 0, longitude: 181), name: nil, accuracy: nil, quality: nil)
        XCTAssertThrowsError(try invalid.encode())
        let store = WaypointStore(file: nil)
        let library = try await store.add(source, now: now, pro: false)
        XCTAssertEqual(library.points.first?.source, .imported)
        XCTAssertEqual(library.points.first?.quality, .low)
        XCTAssertNil(library.points.first?.fixTime)
        XCTAssertEqual(library.milestones.deviceCount, 0)
        do {
            _ = try await store.add(source, now: now, pro: true)
            XCTFail("Importing the same coordinate twice should be rejected")
        } catch { XCTAssertEqual(error as? LibraryError, .duplicate) }
    }

    func testWaypointFileUsesSameSizeLimitAndValidation() throws {
        let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("latlong")
        defer { try? FileManager.default.removeItem(at: url) }
        let code = ShareCode(coordinate: coordinate, name: nil, accuracy: nil, quality: nil)
        try Data(code.encode().utf8).write(to: url)
        XCTAssertEqual(try ShareCode.decode(ShareCode.readFile(url)), code)
        try Data(repeating: 65, count: 1025).write(to: url)
        XCTAssertThrowsError(try ShareCode.readFile(url))
    }

    func testCSVEscapingFormulaSafetyAndColumns() throws {
        let point = Waypoint(seq: 7, projectID: nil, coordinate: coordinate, accuracy: nil, fixTime: nil, savedTime: now,
                             name: " =SUM(1,2)\"\nnext", source: .imported, quality: .unknown, legacyExport: true)
        let data = ExportSnapshot(project: "Field, \"A\"", points: [point]).data(for: .csv)
        XCTAssertEqual(Array(data.prefix(3)), [0xef, 0xbb, 0xbf])
        let csv = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(csv.contains("saved_time_utc,name,source,quality\r\n7,"))
        XCTAssertTrue(csv.contains("\"Field, \"\"A\"\"\""))
        XCTAssertTrue(csv.contains(",,," + "2023-11-14T22:13:20.000Z"))
        XCTAssertTrue(csv.contains("\"' =SUM(1,2)\"\"\nnext\",imported,unknown\r\n"))
    }

    func testGPXSchemaSequenceAndKMLCoordinateOrder() throws {
        let first = Waypoint(seq: 1, projectID: nil, coordinate: coordinate, accuracy: 6, fixTime: now, savedTime: now,
                             name: "A & <B>", source: .device, quality: .good, legacyExport: true)
        let second = Waypoint(seq: 2, projectID: nil, coordinate: coordinate, accuracy: nil, fixTime: nil, savedTime: now,
                              name: "C", source: .imported, quality: .unknown, legacyExport: true)
        let snapshot = ExportSnapshot(project: "Demo", points: [second, first])
        let parser = XMLParser(data: snapshot.data(for: .gpx))
        parser.shouldProcessNamespaces = true
        let gpx = GPXProbe()
        parser.delegate = gpx
        XCTAssertTrue(parser.parse(), parser.parserError?.localizedDescription ?? "")
        XCTAssertEqual(gpx.namespace, "http://www.topografix.com/GPX/1/1")
        XCTAssertEqual(gpx.version, "1.1")
        XCTAssertEqual(gpx.rows, [["time", "name", "extensions"], ["name", "extensions"]])
        XCTAssertEqual(gpx.sequences, ["1", "2"])
        XCTAssertEqual(gpx.accuracies, ["6.0"])
        XCTAssertEqual(gpx.names, ["A & <B>", "C"])
        let kml = snapshot.data(for: .kml)
        XCTAssertTrue(XMLParser(data: kml).parse())
        let text = String(decoding: kml, as: UTF8.self)
        XCTAssertTrue(text.contains("<coordinates>139.772461"))
        XCTAssertTrue(text.contains("A &amp; &lt;B&gt;"))
    }

    func testGPXAntimeridianAndSmallDecimal() {
        let point = Waypoint(seq: 1, projectID: nil, coordinate: Coordinate(latitude: 0.00000001, longitude: 180),
                             accuracy: 6, fixTime: now, savedTime: now, name: "Meridian",
                             source: .device, quality: .good, legacyExport: true)
        let snapshot = ExportSnapshot(project: "Demo", points: [point])
        let gpx = String(decoding: snapshot.data(for: .gpx), as: UTF8.self)
        XCTAssertTrue(gpx.contains("<wpt lat=\"0.00000001\" lon=\"-180.0\">"))
        let csv = String(decoding: snapshot.data(for: .csv), as: UTF8.self)
        XCTAssertTrue(csv.contains(",0.00000001,180.0,"))
    }

    func testPaidStartTrialClaimAndClockRollback() {
        let start = now
        let old = start.addingTimeInterval(-365 * 86_400)
        var entitlement = Entitlement(firstOpen: old)
        XCTAssertFalse(entitlement.hasPro(at: start))
        entitlement.beginPaidVersion(at: start, free: false)
        XCTAssertEqual(entitlement.trialStart, start)
        let later = start.addingTimeInterval(5 * 86_400)
        entitlement.apply(PurchaseReceipt(kind: .trial, originalDate: later, signedAt: later, revoked: false))
        XCTAssertEqual(entitlement.trialStart, start)
        XCTAssertTrue(entitlement.hasPro(at: entitlement.trialEnd.addingTimeInterval(-1)))
        XCTAssertFalse(entitlement.hasPro(at: entitlement.trialEnd))
        let end = entitlement.trialEnd
        entitlement.beginPaidVersion(at: end, free: false)
        XCTAssertFalse(entitlement.hasPro(at: start))
        XCTAssertTrue(entitlement.hasPro(at: start, free: true))
    }

    func testVerifiedBuyoutRestorationAndRefund() throws {
        var access = Entitlement(firstOpen: now, proStartedAt: now)
        let previous = now.addingTimeInterval(-14 * 86_400)
        access.apply(PurchaseReceipt(kind: .trial, originalDate: previous, signedAt: now, revoked: false))
        XCTAssertEqual(access.trialStart, previous)
        let afterTrial = access.trialEnd.addingTimeInterval(1)
        let buy = PurchaseReceipt(kind: .pro, originalDate: now, signedAt: now, revoked: false)
        access.apply(buy)
        XCTAssertTrue(try JSONDecoder().decode(Entitlement.self, from: JSONEncoder().encode(access)).hasPro(at: afterTrial))
        access.apply(PurchaseReceipt(kind: .pro, originalDate: now, signedAt: afterTrial, revoked: true))
        access.apply(buy)
        XCTAssertFalse(access.hasPro(at: afterTrial))
        access.apply(PurchaseReceipt(kind: .pro, originalDate: afterTrial, signedAt: afterTrial.addingTimeInterval(5), revoked: false))
        XCTAssertTrue(access.hasPro(at: afterTrial))
    }

    func testCoreReviewRequiresThreeActionsOnTwoLocalDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let firstDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 23)))
        let nextDay = firstDay.addingTimeInterval(2 * 3600)
        let empty = try JSONDecoder().decode(CoreReviewProgress.self, from: Data("{}".utf8))
        XCTAssertFalse(empty.isEligible)
        var progress = CoreReviewProgress.recording(empty, at: firstDay, calendar: calendar)
        var twoDays = progress
        twoDays.record(at: nextDay, calendar: calendar)
        XCTAssertFalse(twoDays.isEligible)
        progress.record(at: firstDay, calendar: calendar)
        XCTAssertFalse(progress.isEligible)

        var sameDay = progress
        sameDay.record(at: firstDay, calendar: calendar)
        XCTAssertFalse(sameDay.isEligible)

        let data = try JSONEncoder().encode(progress)
        progress = try JSONDecoder().decode(CoreReviewProgress.self, from: data)
        progress.record(at: nextDay, calendar: calendar)
        XCTAssertTrue(progress.isEligible)
    }

    func testMilestoneAndReviewEligibility() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var milestone = Milestones()
        for _ in 0..<9 { milestone.recordDevicePoint(at: now, calendar: calendar) }
        XCTAssertFalse(milestone.hasCard)
        milestone.recordDevicePoint(at: now, calendar: calendar)
        XCTAssertTrue(milestone.hasCard)
        milestone.completedShare = true
        XCTAssertFalse(milestone.canRequestReview)
        milestone.recordDevicePoint(at: now.addingTimeInterval(86_400), calendar: calendar)
        XCTAssertTrue(milestone.canRequestReview)
        milestone.reviewAttempted = true
        XCTAssertFalse(milestone.canRequestReview)
    }

    func testStoreQRCodeCarriesOnlyStoreURL() throws {
        XCTAssertNil(CardQR.storeURL(""))
        XCTAssertNil(CardQR.storeURL("123?latitude=35"))
        let url = try XCTUnwrap(CardQR.storeURL("1234567890"))
        let qr = try XCTUnwrap(CardQR.image(for: url))
        let image = CIImage(cgImage: qr)
        let boxed = image.transformed(by: CGAffineTransform(translationX: 32, y: 32))
            .composited(over: CIImage(color: .white).cropped(to: image.extent.insetBy(dx: -64, dy: -64)
                .offsetBy(dx: 32, dy: 32)))
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                               options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let code = try XCTUnwrap(detector.features(in: boxed).first as? CIQRCodeFeature)
        XCTAssertEqual(code.messageString, "https://apps.apple.com/app/id1234567890")
    }

    func testWaypointFilePreviewsTheSamePayloadAsPastedCode() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".latlong")
        defer { try? FileManager.default.removeItem(at: url) }
        let point = ShareCode(coordinate: Coordinate(latitude: 35.7, longitude: 139.7), name: "Trail",
                              accuracy: nil, quality: nil)
        let text = try point.encode()
        try Data(("  " + text + "\n").utf8).write(to: url)
        XCTAssertEqual(try ShareCode.decode(ShareCode.readFile(url)), point)
        try Data(repeating: 65, count: ShareCode.maxBytes + 1).write(to: url)
        XCTAssertThrowsError(try ShareCode.readFile(url))
    }

    func testShareCardPNGDimensionsAndPlaceholder() throws {
        let card = CardContent(heading: "Meeting point", name: nil, coordinates: nil, accuracy: nil,
                               appName: "LatLong", caption: "#LatLong", qrLabel: "Download QR", storeURL: nil, retry: 0)
        let png = try XCTUnwrap(CardRenderer.png(card))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let raster = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(raster.width, 1080)
        XCTAssertEqual(raster.height, 1350)
        XCTAssertEqual(card.accessibilityText, "Meeting point · #LatLong")
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                               options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        XCTAssertTrue(detector.features(in: CIImage(cgImage: raster)).isEmpty)
    }
}

private final class GPXProbe: NSObject, XMLParserDelegate {
    var namespace: String?
    var version: String?
    var rows: [[String]] = []
    var sequences: [String] = []
    var accuracies: [String] = []
    var names: [String] = []
    private var stack: [String] = []
    private var currentText = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if elementName == "gpx" { namespace = namespaceURI; version = attributeDict["version"] }
        if elementName == "wpt" {
            XCTAssertEqual(namespaceURI, namespace)
            XCTAssertNotNil(attributeDict["lat"].flatMap(Double.init))
            XCTAssertNotNil(attributeDict["lon"].flatMap(Double.init))
            rows.append([])
        } else if stack.last == "wpt" {
            rows[rows.count - 1].append(elementName)
        }
        currentText = ""
        stack.append(elementName)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { currentText += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        _ = stack.popLast()
        switch elementName {
        case "seq":
            XCTAssertEqual(namespaceURI, "urn:com.hgsldswk.latlong:1")
            sequences.append(currentText)
        case "horizontalAccuracyMeters": accuracies.append(currentText)
        case "name":
            if stack.last == "wpt" { names.append(currentText) }
        default: break
        }
    }
}
