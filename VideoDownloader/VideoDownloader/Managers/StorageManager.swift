//
//  StorageManager.swift
//  VideoDownloader
//
//  Created by Keerthika on 04/09/25.
//

import Foundation
import UIKit

class StorageManager {
    static func getFreeDiskSpace() -> Int64 {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let free = attrs[.systemFreeSize] as? NSNumber { return free.int64Value }
        } catch { print("❌ free space error:", error) }
        return 0
    }

    static func documentsDirectory() -> URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    static func localFileURL(for fileName: String) -> URL {
        return documentsDirectory().appendingPathComponent(fileName)
    }
}
