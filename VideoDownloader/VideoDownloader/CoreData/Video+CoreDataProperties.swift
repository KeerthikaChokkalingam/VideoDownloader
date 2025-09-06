//
//  Video+CoreDataProperties.swift
//  VideoDownloader
//
//  Created by Keerthika on 05/09/25.
//
//

import Foundation
import CoreData


extension Video {
    
    var daysLeft: Int {
        guard let expiry = expiryDate else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
        return max(days, 0)
    }
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Video> {
        return NSFetchRequest<Video>(entityName: "Video")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var title: String?
    @NSManaged public var filePath: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var expiryDate: Date?
    @NSManaged public var isExpired: Bool
    @NSManaged public var progress: Double

}

extension Video : Identifiable {

}
