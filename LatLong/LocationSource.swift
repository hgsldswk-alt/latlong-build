import CoreLocation
import SwiftUI

@MainActor
final class LocationSource: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum State: Equatable { case waiting, noSignal, denied, good, low }

    @Published private(set) var fix: Fix?
    @Published private(set) var state: State = .waiting
    private var manager: CLLocationManager?
    private var clock: Task<Void, Never>?
    private var waitingSince = Date()
    private var active = false
    private var requested = false
    private let fixture: String?

    init(fixture: String?) {
        self.fixture = fixture
        super.init()
    }

    func setActive(_ active: Bool) {
        guard active != self.active else { return }
        self.active = active
        if !active {
            manager?.stopUpdatingLocation()
            clock?.cancel()
            clock = nil
            fix = nil
            return
        }
        waitingSince = Date()
        state = .waiting
        if fixture == nil {
            if manager == nil {
                let manager = CLLocationManager()
                manager.desiredAccuracy = kCLLocationAccuracyBest
                manager.distanceFilter = kCLDistanceFilterNone
                manager.delegate = self
                self.manager = manager
            }
            updateAuthorization()
        }
        tick()
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    func usableFix(at now: Date) -> Fix? {
        guard active, let fix, fix.isUsable(at: now) else { return nil }
        return fix
    }

    private func tick() {
        let now = Date()
        if let fixture {
            let low = fixture == "low"
            switch fixture {
            case "denied": state = .denied
            case "waiting": state = .noSignal
            default:
                accept(Fix(coordinate: Coordinate(latitude: low ? 35.713900 : 35.713842,
                                                  longitude: low ? 139.772610 : 139.772461),
                           accuracy: low ? 86 : 6, time: now, reduced: low), now: now)
            }
            return
        }
        guard state != .denied, usableFix(at: now) == nil else { return }
        if fix != nil {
            fix = nil
            waitingSince = now
        }
        state = now.timeIntervalSince(waitingSince) >= 15 ? .noSignal : .waiting
    }

    private func updateAuthorization() {
        guard active, fixture == nil, let manager else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            state = .waiting
            if !requested {
                requested = true
                manager.requestWhenInUseAuthorization()
            }
        case .restricted, .denied:
            manager.stopUpdatingLocation()
            fix = nil
            state = .denied
        case .authorizedAlways, .authorizedWhenInUse:
            if state == .denied {
                waitingSince = Date()
                state = .waiting
            }
            manager.startUpdatingLocation()
        @unknown default:
            state = .waiting
        }
    }

    private func accept(_ fix: Fix, now: Date) {
        guard active, state != .denied, fix.isUsable(at: now),
              self.fix.map({ $0.time <= fix.time }) ?? true else { return }
        self.fix = fix
        state = fix.quality == .good ? .good : .low
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if let fix, manager.accuracyAuthorization == .reducedAccuracy, !fix.reduced {
            accept(Fix(coordinate: fix.coordinate, accuracy: fix.accuracy, time: fix.time, reduced: true), now: Date())
        }
        updateAuthorization()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways else { return }
        let now = Date()
        for location in locations.reversed() {
            let fix = Fix(coordinate: Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
                          accuracy: location.horizontalAccuracy, time: location.timestamp,
                          reduced: manager.accuracyAuthorization == .reducedAccuracy)
            guard fix.isUsable(at: now) else { continue }
            accept(fix, now: now)
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .denied { updateAuthorization() }
    }
}
