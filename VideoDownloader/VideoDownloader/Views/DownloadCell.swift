//
//  DownloadCell.swift
//  VideoDownloader
//
//  Created by Keerthika on 04/09/25.
//

import UIKit

class DownloadCell: UITableViewCell {
    static let reuseIdentifier = "VideoDownloadCell"

    let titleLabel = UILabel()
    let actionButton = UIButton(type: .system)       // Download / Open / Retry
    let pauseResumeButton = UIButton(type: .system)  // Pause / Resume
    let progressView = UIProgressView(progressViewStyle: .default)

    // Callbacks
    var startDownloadAction: (() -> Void)?
    var pauseDownloadAction: (() -> Void)?
    var resumeDownloadAction: (() -> Void)?
    var retryDownloadAction: (() -> Void)?
    var openFileAction: (() -> Void)?

    private var isPaused = false
    private var isDownloading = false
    private var hasFailed = false
    private var isDownloaded = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    private func setupUI() {
            titleLabel.font = .systemFont(ofSize: 16, weight: .medium)
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
    
            actionButton.setTitle("Download", for: .normal)
            actionButton.translatesAutoresizingMaskIntoConstraints = false
            actionButton.addTarget(self, action: #selector(onActionTap), for: .touchUpInside)
    
            pauseResumeButton.setTitle("Pause", for: .normal)
            pauseResumeButton.translatesAutoresizingMaskIntoConstraints = false
            pauseResumeButton.addTarget(self, action: #selector(onPauseResumeTap), for: .touchUpInside)
            pauseResumeButton.isHidden = true  // hidden by default
    
            progressView.translatesAutoresizingMaskIntoConstraints = false
            progressView.progress = 0.0
            progressView.trackTintColor = UIColor.systemGray5
            progressView.tintColor = UIColor.systemBlue
    
            contentView.addSubview(titleLabel)
            contentView.addSubview(actionButton)
            contentView.addSubview(pauseResumeButton)
            contentView.addSubview(progressView)
    
            NSLayoutConstraint.activate([
                titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
                titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionButton.leadingAnchor, constant: -10),
    
                actionButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),
                actionButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
    
                pauseResumeButton.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -10),
                pauseResumeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
    
                progressView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
                progressView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),
                progressView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
                progressView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
                progressView.heightAnchor.constraint(equalToConstant: 4)
            ])
        }

    private func styleButton(_ button: UIButton) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.1)
        button.setTitleColor(.systemBlue, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        button.layer.cornerRadius = 8
        button.clipsToBounds = true
    }

    @objc private func onActionTap() {
        if isDownloaded {
            openFileAction?()
        } else if hasFailed {
            retryDownloadAction?()
        } else if !isDownloading {
            startDownloadAction?()
        }
    }

    @objc private func onPauseResumeTap() {
        if isPaused {
            resumeDownloadAction?()
        } else {
            pauseDownloadAction?()
        }
        isPaused.toggle()
        updateUI()
    }

    func configure(title: String,
                   progress: Float,
                   downloading: Bool = false,
                   failed: Bool = false,
                   paused: Bool = false,
                   downloaded: Bool = false) {
        titleLabel.text = title
        progressView.progress = progress
        isDownloading = downloading
        hasFailed = failed
        isPaused = paused
        isDownloaded = downloaded
        updateUI()
    }

    private func updateUI() {
        if isDownloaded {
            actionButton.setTitle("Open", for: .normal)
            pauseResumeButton.isHidden = true
        } else if hasFailed {
            actionButton.setTitle("Retry", for: .normal)
            pauseResumeButton.isHidden = true
        } else if isDownloading {
            actionButton.setTitle("Downloading…", for: .normal)
            pauseResumeButton.isHidden = false
            pauseResumeButton.setTitle(isPaused ? "Resume" : "Pause", for: .normal)
        } else {
            actionButton.setTitle("Download", for: .normal)
            pauseResumeButton.isHidden = true
        }
    }
}
