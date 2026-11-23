import Foundation
import MapKit
import UIKit
import CoreLocation

/// Directions hand off to Apple Maps, shared by Shop Detail, Visit Detail,
/// Want To Go, and the Shared Shop Landing. A coordinate opens Maps at the
/// pin; an address opens Maps with a directions link, so a shop outside
/// the directory still gets directions from its street address.
enum Directions {
    /// Driving directions to a coordinate, labeled with the shop name.
    static func open(coordinate: CLLocationCoordinate2D, name: String) {
        let placemark = MKPlacemark(coordinate: coordinate, addressDictionary: nil)
        let item = MKMapItem(placemark: placemark)
        item.name = name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    /// Driving directions to a street address, through the Maps link.
    /// Does nothing when the address is blank.
    static func open(address: String, name: String) {
        guard let url = ShareText.mapsDirectionsURL(address: address, name: name) else { return }
        UIApplication.shared.open(url)
    }
}
