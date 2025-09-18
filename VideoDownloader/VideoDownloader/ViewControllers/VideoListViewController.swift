//
//  VideoListViewController.swift
//  VideoDownloader
//
//  Created by Keerthika on 05/09/25.
//


import UIKit
import AVKit
import CoreData

class VideoListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    
    var tableView: UITableView!
    var downloadedVideos: [Video] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Downloaded Videos"
        view.backgroundColor = .white
        
        tableView = UITableView(frame: view.bounds, style: .plain)
        tableView.dataSource = self
        tableView.delegate = self
//        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        
        loadDownloadedVideos()
    }
    
    /// Load all mp4 files from Documents directory
//    func loadDownloadedVideos() {
//        let fileManager = FileManager.default
//        let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
//        
//        do {
//            let files = try fileManager.contentsOfDirectory(at: docsURL, includingPropertiesForKeys: nil)
//            downloadedVideos = files.filter { $0.pathExtension == "mp4" }
//            
//            tableView.reloadData()
//        } catch {
//            print("❌ Error loading files: \(error)")
//        }
//    }
//    func loadDownloadedVideos() {
//        let context = (UIApplication.shared.delegate as! AppDelegate).persistentContainer.viewContext
//        let fetchRequest: NSFetchRequest<Video> = Video.fetchRequest()
//        
//        do {
//            downloadedVideos = try context.fetch(fetchRequest)  // ✅ Now Core Data objects
//            tableView.reloadData()
//        } catch {
//            print("❌ Error fetching videos: \(error)")
//        }
//    }
    func loadDownloadedVideos() {
        let context = (UIApplication.shared.delegate as! AppDelegate).persistentContainer.viewContext
        let fetchRequest: NSFetchRequest<Video> = Video.fetchRequest()
        
        do {
            let videos = try context.fetch(fetchRequest)
            
            // Remove duplicates based on filePath
            var seen = Set<String>()
            downloadedVideos = videos.filter { video in
                if let path = video.filePath, !seen.contains(path) {
                    seen.insert(path)
                    return true
                }
                return false
            }
            
            tableView.reloadData()
        } catch {
            print("❌ Error fetching videos: \(error)")
        }
    }


    func remainingValidityDays(for video: Video) -> Int {
        guard let expiryDate = video.expiryDate else { return 0 }
        let daysLeft = Calendar.current.dateComponents([.day], from: Date(), to: expiryDate).day ?? 0
        return max(daysLeft, 0) // prevent negatives
    }

    // MARK: - UITableView DataSource
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return downloadedVideos.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
//        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
//        let videoURL = downloadedVideos[indexPath.row]
//        cell.textLabel?.text = videoURL.lastPathComponent
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell") ??
                       UITableViewCell(style: .subtitle, reuseIdentifier: "cell") // ✅ subtitle style
            
        let video = downloadedVideos[indexPath.row]
        cell.textLabel?.text = video.filePath

        if let expiryDate = video.expiryDate {
            let daysLeft = remainingValidityDays(for: video)
            if daysLeft > 0 {
                cell.detailTextLabel?.text = "Expires in \(daysLeft) days"
            } else {
                cell.detailTextLabel?.text = "Expired"
            }
        }

        // Add delete (trash) button on the right
        let deleteButton = UIButton(type: .system)
        deleteButton.setImage(UIImage(systemName: "trash"), for: .normal)
        deleteButton.tintColor = .red
        deleteButton.tag = indexPath.row
        deleteButton.addTarget(self, action: #selector(deleteButtonTapped(_:)), for: .touchUpInside)
        deleteButton.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        cell.accessoryView = deleteButton
        
        return cell
        
        
    }
    
    // MARK: - UITableView Delegate
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let videoURL = downloadedVideos[indexPath.row]
        let url = URL(fileURLWithPath: videoURL.filePath!)
        playVideo(url: url)
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
    
    // MARK: - Delete Handling
    @objc private func deleteButtonTapped(_ sender: UIButton) {
        let index = sender.tag
        let videoURL = downloadedVideos[index]
        
        let alert = UIAlertController(
            title: "Delete Video",
            message: "Are you sure you want to delete \"\(videoURL.filePath)\"?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive, handler: { _ in
            self.deleteVideo(at: index)
        }))
        
        present(alert, animated: true)
    }
    // In VideoListViewController
    private func deleteVideo(at index: Int) {
        let fileURL = downloadedVideos[index]
        let url = URL(fileURLWithPath: fileURL.filePath!)
        do {
            try FileManager.default.removeItem(at: url)
            downloadedVideos.remove(at: index)
            tableView.deleteRows(at: [IndexPath(row: index, section: 0)], with: .automatic)

            // Notify DownloadsViewController
            NotificationCenter.default.post(
                name: .videoDeleted,
                object: fileURL
            )
        } catch {
            print("❌ Error deleting file: \(error)")
        }
    }

}
