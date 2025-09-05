//
//  StorageManager.swift
//  VideoDownloader
//
//  Created by Keerthika on 04/09/25.
//

import Foundation

class StorageManager {
    
    /// Returns free disk space in bytes
    static func getFreeDiskSpace() -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let freeSpace = attributes[.systemFreeSize] as? NSNumber {
                return freeSpace.int64Value
            }
        } catch {
            print("❌ Error getting free space: \(error)")
        }
        return 0
    }
    
    /// Returns the app's Documents directory URL
    static func documentsDirectory() -> URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    /// Returns the full local file URL for a video filename
    static func localFileURL(for fileName: String) -> URL {
        return documentsDirectory().appendingPathComponent(fileName)
    }
}
