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

class DownloadsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate,DownloadManagerDelegate {

    // UI
    private var tableView: UITableView!

    // Data
    private var videos: [VideoItem] = []
    private var progressDict: [URL: Float] = [:]
    private var downloadingSet: Set<URL> = []
    private var pausedSet = Set<URL>()
    private var failedSet = Set<URL>()

    // Activity indicator while fetching remote index
    private let spinner = UIActivityIndicatorView(style: .large)
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleVideoDeleted(_:)),
                name: .videoDeleted,
                object: nil
            )
        title = "Available Videos"
        view.backgroundColor = .systemBackground
        DownloadManager.shared.delegate = self
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
    @objc private func handleVideoDeleted(_ notification: Notification) {
        if let url = notification.object as? URL {
            progressDict.removeValue(forKey: url)
            downloadingSet.remove(url)
            pausedSet.remove(url)
            failedSet.remove(url)

            if let row = videos.firstIndex(where: { $0.url == url }) {
                tableView.reloadRows(at: [IndexPath(row: row, section: 0)], with: .none)
            }
        }
    }

    @objc private func openDownloads() {
        let fileManager = FileManager.default
        let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!

        do {
            let files = try fileManager.contentsOfDirectory(at: docsURL, includingPropertiesForKeys: nil)
            let mp4Files = files.filter { $0.pathExtension == "mp4" }

            if mp4Files.isEmpty {
                let alert = UIAlertController(title: "No Downloads",
                                              message: "You don’t have any downloaded videos yet.",
                                              preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            } else {
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
    private func fetchRemoteVideoList() {
        guard let indexURL = URL(string: "https://test-videos.co.uk/bigbuckbunny/mp4-h264/") else {
            loadFallbackSamples()
            return
        }

        spinner.startAnimating()

        let task = URLSession.shared.dataTask(with: indexURL) { [weak self] data, response, error in
            defer { DispatchQueue.main.async { self?.spinner.stopAnimating() } }
            guard let self = self else { return }
            if let error = error {
                print("Failed to fetch index:", error)
                self.loadFallbackSamples()
                return
            }
            guard let data = data else { self.loadFallbackSamples(); return }
            let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            let pattern = "<a[^>]+href=[\"']([^\"']+?\\.mp4)[\"']"
            let regex: NSRegularExpression
            do { regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) }
            catch { print("Regex failed:", error); self.loadFallbackSamples(); return }

            let nsHtml = html as NSString
            let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHtml.length))
            var discovered: [URL] = []
            var seen = Set<String>()
            for m in matches {
                guard m.numberOfRanges >= 2 else { continue }
                let hrefRange = m.range(at: 1)
                let href = nsHtml.substring(with: hrefRange)
                if let resolved = self.resolveHref(href: href, base: indexURL) {
                    let key = resolved.absoluteString
                    if !seen.contains(key) {
                        seen.insert(key)
                        discovered.append(resolved)
                    }
                }
            }
            if discovered.isEmpty { DispatchQueue.main.async { self.loadFallbackSamples() }; return }
            self.videos = discovered.map { VideoItem(title: $0.lastPathComponent, url: $0) }
            DispatchQueue.main.async { self.tableView.reloadData() }
        }
        task.resume()
    }

    private func resolveHref(href: String, base: URL) -> URL? {
        var cleaned = href.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("//") { cleaned = "https:" + cleaned }
        if let abs = URL(string: cleaned), abs.scheme != nil { return abs }
        return URL(string: cleaned, relativeTo: base)?.absoluteURL
    }

    private func loadFallbackSamples() {
        let sampleList: [VideoItem] = [
            VideoItem(title: "Big Buck Bunny (10s)", url: URL(string: "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_1MB.mp4")!),
            VideoItem(title: "Big Buck Bunny (30s)", url: URL(string: "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_30s_5MB.mp4")!)
        ]
        DispatchQueue.main.async {
            self.videos = sampleList
            self.tableView.reloadData()
        }
    }

    // MARK: - Table
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { videos.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        guard let cell = tableView.dequeueReusableCell(withIdentifier: DownloadCell.reuseIdentifier, for: indexPath) as? DownloadCell else {
            return UITableViewCell()
        }
        
        let item = videos[indexPath.row]
        let fileExists = FileManager.default.fileExists(atPath: localFileURL(for: item).path)
        let progress: Float
        if fileExists {
            progress = 1.0   // always 100% if file is already saved
        } else {
            progress = progressDict[item.url] ?? 0.0
        }
        let isDownloading = downloadingSet.contains(item.url)
        let isPaused = pausedSet.contains(item.url)
        let hasFailed = failedSet.contains(item.url)

    
        cell.configure(
            title: item.title,
            progress: progress,
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
        cell.openFileAction = { [weak self] in
            guard let self = self else { return }
            self.openDownloadedVideo(at: self.localFileURL(for: item))
        }

        return cell
    }

    // Local destination in Documents folder
    private func localFileURL(for item: VideoItem) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(item.url.lastPathComponent)
    }

    private func updateProgress(for url: URL, progress: Float) {
        DispatchQueue.main.async {
            if let row = self.videos.firstIndex(where: { $0.url == url }),
               let cell = self.tableView.cellForRow(at: IndexPath(row: row, section: 0)) as? DownloadCell {
                cell.updateProgress(progress)
            }
        }
    }

    // Helper to reload a cell (main thread)
    private func reloadCell(for item: VideoItem) {
        DispatchQueue.main.async {
            if let row = self.videos.firstIndex(where: { $0.url == item.url }) {
                self.tableView.reloadRows(at: [IndexPath(row: row, section: 0)], with: .none)
            }
        }
    }

    private func reloadCell(for url: URL) {
        DispatchQueue.main.async {
            if let row = self.videos.firstIndex(where: { $0.url == url }) {
                self.tableView.reloadRows(at: [IndexPath(row: row, section: 0)], with: .none)
            }
        }
    }

    // MARK: - Playback
    private func openDownloadedVideo(at url: URL) {
        let player = AVPlayer(url: url)
        let vc = AVPlayerViewController()
        vc.player = player
        present(vc, animated: true) { player.play() }
    }
    // MARK: - Download control (pause/resume working)

    func downloadProgress(for url: URL, progress: Float) {
        progressDict[url] = progress
        DispatchQueue.main.async {
            if let row = self.videos.firstIndex(where: { $0.url == url }),
               let cell = self.tableView.cellForRow(at: IndexPath(row: row, section: 0)) as? DownloadCell {
                cell.updateProgress(progress)
            }
        }
    }


    func downloadCompleted(for url: URL, location: URL) {
            progressDict[url] = 1.0
            downloadingSet.remove(url)
            pausedSet.remove(url)
            failedSet.remove(url)
            reloadCell(for: url)
    }

    func downloadFailed(for url: URL, error: Error) {
        failedSet.insert(url)
            downloadingSet.remove(url)
            pausedSet.remove(url)
            progressDict[url] = 0.0
            reloadCell(for: url)
    }

    func downloadNotEnoughSpace(for url: URL) {
        let alert = UIAlertController(title: "Not Enough Space",
                                      message: "Cannot download \(url.lastPathComponent).",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    private func startDownload(item: VideoItem) {
            downloadingSet.insert(item.url)
            failedSet.remove(item.url)
            pausedSet.remove(item.url)
            progressDict[item.url] = 0.0
            reloadCell(for: item)
            DownloadManager.shared.startDownload(from: item.url)
    }

    private func pauseDownload(item: VideoItem) {
        DownloadManager.shared.pauseDownload(for: item.url)
            downloadingSet.remove(item.url)
            pausedSet.insert(item.url)
            reloadCell(for: item)
    }

    private func resumeDownload(item: VideoItem) {
        DownloadManager.shared.resumeDownload(for: item.url)
            pausedSet.remove(item.url)
            downloadingSet.insert(item.url)
            reloadCell(for: item)
    }

    private func retryDownload(item: VideoItem) {
        DownloadManager.shared.startDownload(from: item.url) // just restart
    }

}

