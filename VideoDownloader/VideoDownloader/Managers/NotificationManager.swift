//
//  NotificationManager.swift
//  VideoDownloader
//
//  Created by Keerthika on 04/09/25.
//

import UIKit

class NotificationManager: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }


}
// Common notification name
extension Notification.Name {
    static let videoDeleted = Notification.Name("videoDeleted")
}
