//
//  DownloadManager.swift
//  VideoDownloader
//
//  Created by Keerthika on 04/09/25.
//


import Foundation
import UserNotifications
import CoreData

protocol DownloadManagerDelegate: AnyObject {
    func downloadProgress(for url: URL, progress: Float)
    func downloadCompleted(for url: URL, location: URL)
    func downloadFailed(for url: URL, error: Error)
    func downloadNotEnoughSpace(for url: URL)
}

class DownloadManager: NSObject {
    
    static let shared = DownloadManager()
    private var resumeDataDict: [URL: Data] = [:]
    private var activeDownloads: [URL: URLSessionDownloadTask] = [:]

    weak var delegate: DownloadManagerDelegate?
    
    private lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.keerthika.VideoDownloader.bgSession")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    // MARK: - Download Control
    
    func startDownload(from url: URL) {
        let requiredSpace: Int64 = 100 * 1024 * 1024
        let freeSpace = StorageManager.getFreeDiskSpace()
        
        if freeSpace < requiredSpace {
            DispatchQueue.main.async { self.delegate?.downloadNotEnoughSpace(for: url) }
            return
        }
        
        guard activeDownloads[url] == nil else { return } // already downloading
        let task = backgroundSession.downloadTask(with: url)
        activeDownloads[url] = task
        task.resume()
    }
    
    func pauseDownload(for url: URL) {
        guard let task = activeDownloads[url] else { return }
        task.cancel { resumeData in
            if let data = resumeData { self.resumeDataDict[url] = data }
        }
        activeDownloads.removeValue(forKey: url)
    }
    
    func resumeDownload(for url: URL) {
        if let data = resumeDataDict[url] {
            let task = backgroundSession.downloadTask(withResumeData: data)
            activeDownloads[url] = task
            task.resume()
            resumeDataDict.removeValue(forKey: url)
        } else {
            startDownload(from: url)
        }
    }
    
    func cancelDownload(for url: URL) {
        guard let task = activeDownloads[url] else { return }
        task.cancel()
        activeDownloads.removeValue(forKey: url)
    }
    
    // MARK: - Expired Cleanup
    
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
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        
        guard let url = downloadTask.originalRequest?.url else { return }
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
        DispatchQueue.main.async { self.delegate?.downloadProgress(for: url, progress: progress) }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        
        guard let srcURL = downloadTask.originalRequest?.url else { return }
        let dest = StorageManager.localFileURL(for: srcURL.lastPathComponent)
        
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            DispatchQueue.main.async {
                self.delegate?.downloadCompleted(for: srcURL, location: dest)
                self.sendDownloadNotification(fileName: srcURL.lastPathComponent)
            }
        } catch {
            DispatchQueue.main.async { self.delegate?.downloadFailed(for: srcURL, error: error) }
        }
        activeDownloads.removeValue(forKey: srcURL)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let url = task.originalRequest?.url else { return }
            
            if let err = error as NSError? {
                if err.domain == NSURLErrorDomain,
                   err.code == NSURLErrorCancelled {
                    // Cancelled on purpose (pause) → don’t mark failed
                    return
                }
                DispatchQueue.main.async {
                    self.delegate?.downloadFailed(for: url, error: err)
                }
            }
            activeDownloads.removeValue(forKey: url)
    }
    
    private func sendDownloadNotification(fileName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Download Complete"
        content.body = "\(fileName) is ready to watch."
        content.sound = .default
        let request = UNNotificationRequest(identifier: fileName, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
