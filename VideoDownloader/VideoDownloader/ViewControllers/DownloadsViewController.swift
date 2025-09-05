//
//  DownloadsViewController.swift
//  VideoDownloader
//
//  Created by Keerthika on 04/09/25.
//

import UIKit
import AVFoundation
import AVKit

// Simple model for items discovered on the remote index page
struct VideoItem {
    let title: String
    let url: URL
}

class DownloadsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, URLSessionDownloadDelegate {
    
    // UI
    private var tableView: UITableView!
    
    // Data
    private var videos: [VideoItem] = []
    private var progressDict: [URL: Float] = [:]
    private var downloadingSet: Set<URL> = []
    var pausedSet = Set<URL>()
    var failedSet = Set<URL>()
    
    
    // Single session used for all foreground downloads (keeps delegate alive)
    private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    // Activity indicator while fetching remote index
    private let spinner = UIActivityIndicatorView(style: .large)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Available Videos"
        view.backgroundColor = .systemBackground
        
        setupTableView()
        setupSpinner()
        
        // Fetch remote list from the test-videos site
        fetchRemoteVideoList()
    }
    
    private func setupTableView() {
        tableView = UITableView(frame: view.bounds, style: .plain)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(DownloadCell.self, forCellReuseIdentifier: DownloadCell.reuseIdentifier)
        view.addSubview(tableView)
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Downloads",
            style: .plain,
            target: self,
            action: #selector(openDownloads)
        )
    }
    @objc private func openDownloads() {
        let fileManager = FileManager.default
        let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        do {
            let files = try fileManager.contentsOfDirectory(at: docsURL, includingPropertiesForKeys: nil)
            let mp4Files = files.filter { $0.pathExtension == "mp4" }
            
            if mp4Files.isEmpty {
                // Show alert if no files
                let alert = UIAlertController(title: "No Downloads",
                                              message: "You don’t have any downloaded videos yet.",
                                              preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            } else {
                // Push the downloads list screen
                let listVC = VideoListViewController()
                navigationController?.pushViewController(listVC, animated: true)
            }
        } catch {
            print("❌ Error checking downloads: \(error)")
        }
    }
    
    private func setupSpinner() {
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12)
        ])
    }
    
    // MARK: - Remote index fetch & parse
    
    /// Fetches the HTML index and parses any .mp4 links into `videos`
    private func fetchRemoteVideoList() {
        // Use canonical site URL (note: user had a small typo earlier; we use the correct domain)
        guard let indexURL = URL(string: "https://test-videos.co.uk/bigbuckbunny/mp4-h264/") else {
            loadFallbackSamples()
            return
        }
        
        spinner.startAnimating()
        
        let task = URLSession.shared.dataTask(with: indexURL) { [weak self] data, response, error in
            defer {
                DispatchQueue.main.async { self?.spinner.stopAnimating() }
            }
            
            guard let self = self else { return }
            if let error = error {
                print("Failed to fetch index:", error)
                self.loadFallbackSamples()
                return
            }
            
            guard let data = data else {
                self.loadFallbackSamples()
                return
            }
            
            // Try decode as UTF-8, fallback to isoLatin1
            let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            
            // Parse <a href="...mp4"> links
            let pattern = "<a[^>]+href=[\"']([^\"']+?\\.mp4)[\"']"
            let regex: NSRegularExpression
            do {
                regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            } catch {
                print("Regex creation failed:", error)
                self.loadFallbackSamples()
                return
            }
            
            let nsHtml = html as NSString
            let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHtml.length))
            
            var discovered: [URL] = []
            var seen = Set<String>()
            
            for m in matches {
                guard m.numberOfRanges >= 2 else { continue }
                let hrefRange = m.range(at: 1)
                let href = nsHtml.substring(with: hrefRange)
                
                // Resolve relative URLs against the index URL
                if let resolved = self.resolveHref(href: href, base: indexURL) {
                    // dedupe by absolute string
                    let key = resolved.absoluteString
                    if !seen.contains(key) {
                        seen.insert(key)
                        discovered.append(resolved)
                    }
                }
            }
            
            if discovered.isEmpty {
                // If parsing failed to find anything, fallback
                DispatchQueue.main.async {
                    self.loadFallbackSamples()
                }
                return
            }
            
            // Create VideoItem list using lastPathComponent as title
            self.videos = discovered.map { VideoItem(title: $0.lastPathComponent, url: $0) }
            
            DispatchQueue.main.async {
                self.tableView.reloadData()
            }
        }
        
        task.resume()
    }
    
    /// Resolve relative or protocol-relative HREF to an absolute URL using the index base
    private func resolveHref(href: String, base: URL) -> URL? {
        var cleaned = href.trimmingCharacters(in: .whitespacesAndNewlines)
        // handle protocol-relative (//example.com/...)
        if cleaned.hasPrefix("//") {
            cleaned = "https:" + cleaned
        }
        // If already absolute
        if let abs = URL(string: cleaned), abs.scheme != nil {
            return abs
        }
        // Otherwise resolve relative to base
        return URL(string: cleaned, relativeTo: base)?.absoluteURL
    }
    
    // MARK: - Fallback samples
    private func loadFallbackSamples() {
        // Keep these minimal — they let the UI still work offline.
        let sampleList: [VideoItem] = [
            VideoItem(title: "Big Buck Bunny (10s)", url: URL(string: "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_1MB.mp4")!),
            VideoItem(title: "Big Buck Bunny (30s)", url: URL(string: "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_30s_5MB.mp4")!)
        ]
        DispatchQueue.main.async {
            self.videos = sampleList
            self.tableView.reloadData()
        }
    }
    
    // MARK: - UITableView DataSource / Delegate
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return videos.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        guard let cell = tableView.dequeueReusableCell(withIdentifier: DownloadCell.reuseIdentifier, for: indexPath) as? DownloadCell else {
            return UITableViewCell()
        }
        
        let item = videos[indexPath.row]
        cell.titleLabel.text = item.title
        cell.progressView.progress = progressDict[item.url] ?? 0.0
        
        let fileExists = FileManager.default.fileExists(atPath: localFileURL(for: item).path)
        let isDownloading = downloadingSet.contains(item.url)
        let isPaused = pausedSet.contains(item.url)
        let hasFailed = failedSet.contains(item.url)

        cell.configure(
            title: item.title,
            progress: progressDict[item.url] ?? 0.0,
            downloading: isDownloading,
            failed: hasFailed,
            paused: isPaused,
            downloaded: fileExists
        )

        // Callbacks
        cell.startDownloadAction = { [weak self] in self?.startDownload(item: item) }
        cell.pauseDownloadAction = { [weak self] in self?.pauseDownload(item: item) }
        cell.resumeDownloadAction = { [weak self] in self?.resumeDownload(item: item) }
        cell.retryDownloadAction = { [weak self] in self?.retryDownload(item: item) }
        cell.openFileAction = { [weak self] in self?.openDownloadedVideo(at: self!.localFileURL(for: item)) }

        return cell
        
    }
    
    // Local destination in Documents folder
    private func localFileURL(for item: VideoItem) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(item.url.lastPathComponent)
    }
    
    // MARK: - Download control
    
    private func startDownload(item: VideoItem) {
        downloadingSet.insert(item.url)
        pausedSet.remove(item.url)
        failedSet.remove(item.url)
        progressDict[item.url] = 0.0
        reloadCell(for: item)
        
        let task = downloadSession.downloadTask(with: item.url)
        task.resume()
    }
    
    private func pauseDownload(item: VideoItem) {
        guard downloadingSet.contains(item.url) else { return }
        downloadingSet.remove(item.url)
        pausedSet.insert(item.url)
        DownloadManager.shared.pauseDownload(for: item.url)
        reloadCell(for: item)
    }
    
    private func resumeDownload(item: VideoItem) {
        guard pausedSet.contains(item.url) else { return }
        pausedSet.remove(item.url)
        downloadingSet.insert(item.url)
        DownloadManager.shared.resumeDownload(for: item.url)
        reloadCell(for: item)
    }
    
    private func retryDownload(item: VideoItem) {
        guard failedSet.contains(item.url) else { return }
        failedSet.remove(item.url)
        startDownload(item: item)
    }
    
    // MARK: - Helper to reload a cell
    private func reloadCell(for item: VideoItem) {
        if let row = videos.firstIndex(where: { $0.url == item.url }) {
            let idx = IndexPath(row: row, section: 0)
            DispatchQueue.main.async {
                self.tableView.reloadRows(at: [idx], with: .none)

            }
        }
    }
    
    
    private func openDownloadedVideo(at url: URL) {
        let player = AVPlayer(url: url)
        let vc = AVPlayerViewController()
        vc.player = player
        present(vc, animated: true) { player.play() }
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    // Progress
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        
        guard let url = downloadTask.originalRequest?.url else { return }
        let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
        progressDict[url] = progress
        reloadCell(for: url)
    }
    
    // Completion
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        
        guard let url = downloadTask.originalRequest?.url else { return }
        
        downloadingSet.remove(url)
        pausedSet.remove(url)
        failedSet.remove(url)
        progressDict[url] = 1.0
        
        if let item = videos.first(where: { $0.url == url }) {
                moveDownloadedFileToDocuments(from: location, for: item)
                reloadCell(for: item)
            }
    }
    
    // Failed
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    
        
        guard let url = task.originalRequest?.url else { return }
        
        if error != nil {
            downloadingSet.remove(url)
            pausedSet.remove(url)
            failedSet.insert(url)
            progressDict[url] = 0.0
            reloadCell(for: url)
        }
    }

    func reloadCell(for url: URL) {
        if let row = videos.firstIndex(where: { $0.url == url }) {
            DispatchQueue.main.async {
                self.tableView.reloadRows(at: [IndexPath(row: row, section: 0)], with: .none)
            }
        }
    }
    private func moveDownloadedFileToDocuments(from location: URL, for item: VideoItem) {
        let destinationURL = localFileURL(for: item)
        let fileManager = FileManager.default

        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: location, to: destinationURL)

            // Update UI-related state on main thread
            DispatchQueue.main.async {
                self.downloadingSet.remove(item.url)
                self.pausedSet.remove(item.url)
                self.failedSet.remove(item.url)
                self.progressDict[item.url] = 1.0
                self.reloadCell(for: item)

                let alert = UIAlertController(title: "Download Complete",
                                              message: "\(item.title) saved.",
                                              preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                alert.addAction(UIAlertAction(title: "View Downloads", style: .default) { _ in
                    let listVC = VideoListViewController()
                    self.navigationController?.pushViewController(listVC, animated: true)
                })
                self.present(alert, animated: true)
            }
        } catch {
            print("❌ Error saving file:", error)
            DispatchQueue.main.async {
                self.downloadingSet.remove(item.url)
                self.failedSet.insert(item.url)
                self.progressDict[item.url] = 0.0
                self.reloadCell(for: item)

                let alert = UIAlertController(title: "Save Failed",
                                              message: error.localizedDescription,
                                              preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
            }
        }
    }

}
