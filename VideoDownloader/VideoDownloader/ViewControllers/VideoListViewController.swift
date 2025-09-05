//
//  VideoListViewController.swift
//  VideoDownloader
//
//  Created by Keerthika on 05/09/25.
//

import UIKit
import AVKit

class VideoListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    
    var tableView: UITableView!
    var downloadedVideos: [URL] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Downloaded Videos"
        view.backgroundColor = .white
        
        // Create TableView
        tableView = UITableView(frame: view.bounds, style: .plain)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        
        loadDownloadedVideos()
    }
    
    /// Load all mp4 files from Documents directory
    func loadDownloadedVideos() {
        let fileManager = FileManager.default
        let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        do {
            let files = try fileManager.contentsOfDirectory(at: docsURL, includingPropertiesForKeys: nil)
            downloadedVideos = files.filter { $0.pathExtension == "mp4" }
            tableView.reloadData()
        } catch {
            print("❌ Error loading files: \(error)")
        }
    }
    
    // MARK: - UITableView DataSource
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return downloadedVideos.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let videoURL = downloadedVideos[indexPath.row]
        cell.textLabel?.text = videoURL.lastPathComponent
        return cell
    }
    
    // MARK: - UITableView Delegate
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let videoURL = downloadedVideos[indexPath.row]
        playVideo(url: videoURL)
    }
    
    /// Play video with AVPlayer
    func playVideo(url: URL) {
        let player = AVPlayer(url: url)
        let playerVC = AVPlayerViewController()
        playerVC.player = player
        present(playerVC, animated: true) {
            player.play()
        }
    }
}
