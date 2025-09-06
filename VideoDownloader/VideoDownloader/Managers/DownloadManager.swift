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
                expiresAt: nil)
            transform(&md)
            metadataMap[key] = md
        }
        persistMetadata()
    }

    // MARK: - Public control

    func startDownload(from url: URL) {
        // check free space
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
            }
            // remove any resume file if present
            if let rurl = resumeDataMap[srcURL] {
                try? FileManager.default.removeItem(at: rurl)
                resumeDataMap.removeValue(forKey: srcURL)
            }

            DispatchQueue.main.async {
                self.delegate?.downloadCompleted(for: srcURL, location: dest)
                self.sendDownloadNotification(fileName: srcURL.lastPathComponent)
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
            // If cancelled by user to pause (NSURLSessionTaskCancelReasonUserInitiated is not always provided),
            // treat Cancelled specially. NSURLErrorCancelled is used for many cancels including pause.
            // We don't mark failure on user-initiated pause/cancel — the pause method writes resume data and caller should update UI.
            if err.domain == NSURLErrorDomain && err.code == NSURLErrorCancelled {
                // Don't notify failure here — pauseDownload handles resumeData save.
                activeDownloads.removeValue(forKey: url)
                return
            }

            DispatchQueue.main.async {
                self.delegate?.downloadFailed(for: url, error: err)
            }
            activeDownloads.removeValue(forKey: url)
            return
        }

        // no error — nothing to do (completion should already be handled in didFinishDownloadingTo)
        activeDownloads.removeValue(forKey: url)
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
    
    func cleanExpiredVideos() {
            let context = CoreDataManager.shared.viewContext
            let fetchRequest: NSFetchRequest<Video> = Video.fetchRequest()
            guard let videos = try? context.fetch(fetchRequest) else { return }
    
            videos.forEach { video in
                if let date = video.createdAt, Date().timeIntervalSince(date) > 30*24*3600 {
                    video.isExpired = true
                    if let filePath = video.filePath {
                        try? FileManager.default.removeItem(at: StorageManager.localFileURL(for: filePath))
                    }
                }
            }
            CoreDataManager.shared.saveContext()
        }
    private func updateCoreData(for url: URL, metadata: DownloadMetadata) {
        let context = CoreDataManager.shared.viewContext
        let fetch: NSFetchRequest<Video> = Video.fetchRequest()
        fetch.predicate = NSPredicate(format: "urlString == %@", url.absoluteString)
    
        let video = (try? context.fetch(fetch).first) ?? Video(context: context)

        // Assign metadata values to video
        video.filePath = metadata.urlString
        video.progress = metadata.progress.magnitudeSquared
        video.title = metadata.localFileName ?? metadata.resumeFileName
        video.createdAt = metadata.createdAt
        video.expiryDate = metadata.expiresAt
        var videoDownload : Bool = false
        // Derive downloaded state from progress
        videoDownload = (video.progress >= 1.0)
        videoDownload = metadata.downloaded
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

}
