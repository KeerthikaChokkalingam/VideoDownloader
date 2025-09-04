//
//  CoreDataManager.swift
//  VideoDownloader
//
//  Created by Keerthika on 05/09/25.
//

import Foundation
import CoreData
import UIKit

final class CoreDataManager {
    static let shared = CoreDataManager()

    private init() {}

    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "VideoDownloader") // name matches .xcdatamodeld
        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                fatalError("Unresolved Core Data error \(error), \(error.userInfo)")
            }
        }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }()

    var viewContext: NSManagedObjectContext { persistentContainer.viewContext }

    func saveContext () {
        let context = viewContext
        if context.hasChanges {
            do { try context.save() }
            catch { let nserror = error as NSError; fatalError("Unresolved error \(nserror), \(nserror.userInfo)") }
        }
    }
}
