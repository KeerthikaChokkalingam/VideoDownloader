//
//  DownloadManager.swift
//  VideoDownloader
//
//  Created by Keerthika on 04/09/25.
//


import Foundation
import UserNotifications
import UIKit
import CoreData
import BackgroundTasks

protocol DownloadManagerDelegate: AnyObject {
    func downloadProgress(for url: URL, progress: Float)
    func downloadCompleted(for url: URL, location: URL)
    func downloadFailed(for url: URL, error: Error)
    func downloadNotEnoughSpace(for url: URL)
}
struct DownloadMetadata: Codable {
    let urlString: String
    var progress: Float
    var localFileName: String?
    var resumeFileName: String?
    var downloaded: Bool
    var createdAt: Date
    var expiresAt: Date? // optional expiry if you want
}

final class DownloadManager: NSObject {
    static let shared = DownloadManager()
    private override init() {
        super.init()
        // recreate session so system can reattach background tasks after relaunch
        _ = backgroundSession
        restoreState()
    }

    weak var delegate: DownloadManagerDelegate?

    private let metadataKey = "com.keerthika.VideoDownloader.metadata"
    private var metadataMap: [String: DownloadMetadata] = [:] // key = url.absoluteString

    private var resumeDataMap: [URL: URL] = [:] // URL -> resume file URL on disk
    private var activeDownloads: [URL: URLSessionDownloadTask] = [:]
    private let maxConcurrentDownloads = 3
    private var pendingDownloads: [URL] = []

    private lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.keerthika.VideoDownloader.bgSession")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        // Important: set waitsForConnectivity if you want system to wait for network
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    // MARK: - metadata persistence
    private func persistMetadata() {
        do {
            let data = try JSONEncoder().encode(Array(metadataMap.values))
            UserDefaults.standard.set(data, forKey: metadataKey)
        } catch {
            print("❌ Failed to persist download metadata:", error)
        }
    }

    private func loadMetadata() {
        guard let data = UserDefaults.standard.data(forKey: metadataKey) else { return }
        do {
            let arr = try JSONDecoder().decode([DownloadMetadata].self, from: data)
            metadataMap = Dictionary(uniqueKeysWithValues: arr.map { ($0.urlString, $0) })
        } catch {
            print("❌ Failed to load metadata:", error)
        }
    }

    private func updateMetadataFor(url: URL, transform: (inout DownloadMetadata) -> Void) {
        let key = url.absoluteString
        if var md = metadataMap[key] {
            transform(&md)
            metadataMap[key] = md
        } else {
            // create default
            var md = DownloadMetadata(
                urlString: key,
                progress: 0,
                localFileName: nil,
                resumeFileName: nil,
                downloaded: false,
                createdAt: Date(),
                expiresAt: Calendar.current.date(byAdding: .day, value: 30, to: Date()))
            transform(&md)
            metadataMap[key] = md
        }
        persistMetadata()
    }

    // MARK: - Public control

    func startDownload(from url: URL) {
        // check free space
        
        if activeDownloads.count >= maxConcurrentDownloads {
                    if !pendingDownloads.contains(url) { pendingDownloads.append(url) }
                    return
                }
        let requiredSpace: Int64 = 100 * 1024 * 1024
        let freeSpace = StorageManager.getFreeDiskSpace()
        if freeSpace < requiredSpace {
            DispatchQueue.main.async { self.delegate?.downloadNotEnoughSpace(for: url) }
            return
        }

        if activeDownloads[url] != nil {
            // already downloading
            return
        }

        // If we have resume data on disk, resume from it
        if let resumeFile = resumeDataMap[url], let resumeData = try? Data(contentsOf: resumeFile) {
            let task = backgroundSession.downloadTask(withResumeData: resumeData)
            task.taskDescription = url.absoluteString
            activeDownloads[url] = task
            updateMetadataFor(url: url) { $0.progress = $0.progress } // ensure entry exists
            task.resume()
            return
        }

        // normal start
        let task = backgroundSession.downloadTask(with: url)
        task.taskDescription = url.absoluteString
        activeDownloads[url] = task
        updateMetadataFor(url: url) { $0.progress = 0 }
        task.resume()
    }
func downloadDidFinish(url: URL) {
    activeDownloads.removeValue(forKey: url)
    if let nextURL = pendingDownloads.first {
        pendingDownloads.removeFirst()
        startDownload(from: nextURL)
    }
}
    func pauseDownload(for url: URL) {
        guard let task = activeDownloads[url] else { return }
        task.cancel { [weak self] resumeData in
            guard let self = self else { return }
            if let resumeData = resumeData {
                // write resumeData to file
                let fileName = "resume-\(UUID().uuidString).dat"
                let fileURL = StorageManager.documentsDirectory().appendingPathComponent(fileName)
                do {
                    try resumeData.write(to: fileURL)
                    self.resumeDataMap[url] = fileURL
                    self.updateMetadataFor(url: url) { $0.resumeFileName = fileName }
                } catch {
                    print("❌ Error saving resume data:", error)
                }
            } else {
                // no resume data produced
            }
        }
        activeDownloads.removeValue(forKey: url)
        // don't call delegate here; caller (VC) will update UI sets. But we still persist metadata progress
    }

    func resumeDownload(for url: URL) {
        // if a resume file exists, start using it; else start fresh
        startDownload(from: url)
        // the activeDownloads map will be updated by startDownload
    }

    func cancelDownload(for url: URL) {
        // cancel and remove resume file if present
        if let task = activeDownloads[url] {
            task.cancel()
            activeDownloads.removeValue(forKey: url)
        }
        if let file = resumeDataMap[url] {
            try? FileManager.default.removeItem(at: file)
            resumeDataMap.removeValue(forKey: url)
            updateMetadataFor(url: url) { $0.resumeFileName = nil }
        }
        // clear metadata for this download if desired (not removing persisted history in this example)
    }

    // Helper to restore background tasks on launch
    private func restoreBackgroundTasks() {
        backgroundSession.getAllTasks { [weak self] tasks in
            guard let self = self else { return }
            for t in tasks {
                if let dt = t as? URLSessionDownloadTask,
                   let urlString = dt.originalRequest?.url?.absoluteString,
                   let url = URL(string: urlString) {
                    dt.taskDescription = url.absoluteString
                    self.activeDownloads[url] = dt
                }
            }
        }
    }

    // MARK: - Helpers: convert resume filename <-> disk
    private func resumeFileURLFor(fileName: String?) -> URL? {
        guard let fileName = fileName else { return nil }
        return StorageManager.documentsDirectory().appendingPathComponent(fileName)
    }

    // MARK: - Notification (local)
    private func sendDownloadNotification(fileName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Download Complete"
        content.body = "\(fileName) is ready to watch."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "download.\(fileName)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

// MARK: - URLSessionDownloadDelegate
extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {

        guard let url = downloadTask.originalRequest?.url else { return }
        guard totalBytesExpectedToWrite > 0 else { return }

        let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)

        // persist progress
        updateMetadataFor(url: url) { $0.progress = progress }

        DispatchQueue.main.async { self.delegate?.downloadProgress(for: url, progress: progress) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let srcURL = downloadTask.originalRequest?.url else { return }
        let dest = StorageManager.localFileURL(for: srcURL.lastPathComponent)

        // remove any prior file
        try? FileManager.default.removeItem(at: dest)

        do {
            try FileManager.default.moveItem(at: location, to: dest)
            // update metadata
            updateMetadataFor(url: srcURL) {
                $0.downloaded = true
                $0.localFileName = srcURL.lastPathComponent
                $0.progress = 1.0
                $0.resumeFileName = nil
                $0.createdAt = Date() // download date
                $0.expiresAt = Calendar.current.date(byAdding: .day, value: 30, to: Date())
            }

            // remove any resume file if present
            if let rurl = resumeDataMap[srcURL] {
                try? FileManager.default.removeItem(at: rurl)
                resumeDataMap.removeValue(forKey: srcURL)
            }
            if let metadata = metadataMap[srcURL.absoluteString] {
                        updateCoreData(for: srcURL, metadata: metadata)
                    }
            DispatchQueue.main.async {
                self.delegate?.downloadCompleted(for: srcURL, location: dest)
                self.sendDownloadNotification(fileName: srcURL.lastPathComponent)
                self.showCompletionAlert(for: srcURL.lastPathComponent)
            }
        } catch {
            DispatchQueue.main.async {
                self.delegate?.downloadFailed(for: srcURL, error: error)
            }
        }

        activeDownloads.removeValue(forKey: srcURL)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let url = task.originalRequest?.url else { return }

        if let err = error as NSError? {
            // Cancelled (pause) — already handled
            if err.domain == NSURLErrorDomain && err.code == NSURLErrorCancelled {
                activeDownloads.removeValue(forKey: url)
                return
            }

            // Timeout error
            if err.domain == NSURLErrorDomain && err.code == NSURLErrorTimedOut {
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.downloadFailed(for: url, error: err)
                    // Optionally, show retry alert
                    self?.showRetryAlert(for: url, error: err)
                }
                activeDownloads.removeValue(forKey: url)
                return
            }

            // Other errors
            DispatchQueue.main.async {
                self.delegate?.downloadFailed(for: url, error: err)
            }
            activeDownloads.removeValue(forKey: url)
            return
        }

        // no error — nothing to do (completion handled in didFinishDownloadingTo)
        activeDownloads.removeValue(forKey: url)
    }

    // Optional helper to show retry alert
    private func showRetryAlert(for url: URL, error: NSError) {
        guard let topVC = UIApplication.shared.connectedScenes
                .filter({ $0.activationState == .foregroundActive })
                .compactMap({ $0 as? UIWindowScene })
                .first?.windows
                .first(where: { $0.isKeyWindow })?.rootViewController else { return }
        let alert = UIAlertController(title: "Download Failed",
                                      message: "Download for \(url.lastPathComponent) failed due to timeout. Retry?",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Retry", style: .default, handler: { _ in
            self.startDownload(from: url)
        }))
        topVC.present(alert, animated: true)
    }

    // When background session finishes events (app was in background), AppDelegate must hold completion handler.
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            if let appDelegate = UIApplication.shared.delegate as? AppDelegate,
               let completion = appDelegate.backgroundCompletionHandler {
                completion() // ✅ now it works
                appDelegate.backgroundCompletionHandler = nil
            }
        }
    }
    
    private func updateCoreData(for url: URL, metadata: DownloadMetadata) {
        let context = CoreDataManager.shared.viewContext
        let fetch: NSFetchRequest<Video> = Video.fetchRequest()
        fetch.predicate = NSPredicate(format: "filePath == %@", url.absoluteString)

        let video = (try? context.fetch(fetch).first) ?? Video(context: context)

        video.filePath = url.absoluteString   // ✅ use url.absoluteString
        video.progress = Double(metadata.progress)
        video.title = metadata.localFileName ?? metadata.resumeFileName
        video.createdAt = metadata.createdAt
        video.expiryDate = metadata.expiresAt
        let expiryDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())
        video.expiryDate = expiryDate ?? Date()
        CoreDataManager.shared.saveContext()
    }

    private func restoreState() {
        loadMetadata()
        restoreBackgroundTasks()
        
        // Inform delegate so UI can refresh from persisted state
        for meta in metadataMap.values {
            if meta.downloaded, let fileName = meta.localFileName {
                let localURL = StorageManager.localFileURL(for: fileName)
                delegate?.downloadCompleted(for: URL(string: meta.urlString)!, location: localURL)
            } else {
                delegate?.downloadProgress(for: URL(string: meta.urlString)!, progress: meta.progress)
            }
        }
    }
    func cleanExpiredVideos() {
        for (urlString, metadata) in metadataMap {
            if metadata.expiresAt ?? Date() <= Date() {
                if let fileName = metadata.localFileName {
                    let fileURL = StorageManager.localFileURL(for: fileName)
                    try? FileManager.default.removeItem(at: fileURL)
                }
                metadataMap.removeValue(forKey: urlString)
            }
        }
        persistMetadata()
    }
    func scheduleCleanExpiredVideosTask() {
        let request = BGProcessingTaskRequest(identifier: "com.myapp.cleanExpiredVideos")
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 24*60*60) // once a day
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to schedule background task: \(error)")
        }
    }
    func handleCleanExpiredVideosTask(task: BGProcessingTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        DownloadManager.shared.cleanExpiredVideos() // delete expired files & metadata

        task.setTaskCompleted(success: true)
        scheduleCleanExpiredVideosTask() // reschedule next
    }
    private func showCompletionAlert(for fileName: String) {
        guard let topVC = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows
            .first(where: { $0.isKeyWindow })?.rootViewController else {
            return
        }
        
        let alert = UIAlertController(
            title: "Download Complete",
            message: "\(fileName) is ready to watch.",
            preferredStyle: .alert
        )
        
        // OK button → just dismiss
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        
        // Go to List button → push VideoListViewController
        alert.addAction(UIAlertAction(title: "Go to List", style: .default, handler: { _ in
            let listVC = VideoListViewController()
            if let nav = topVC as? UINavigationController {
                nav.pushViewController(listVC, animated: true)
            } else {
                topVC.navigationController?.pushViewController(listVC, animated: true)
            }
        }))
        
        topVC.present(alert, animated: true)
    }

}
extension DownloadMetadata {
    var remainingDays: Int {
        guard let expiry = expiresAt else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
        return max(days, 0)
    }
}
