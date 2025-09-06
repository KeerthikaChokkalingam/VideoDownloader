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
     let actionButton = UIButton(type: .system)
     let pauseResumeButton = UIButton(type: .system)
     let progressView = UIProgressView(progressViewStyle: .default)
     let progressLabel = UILabel() 

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
        // Background card style
        contentView.backgroundColor = .clear
        let cardView = UIView()
        cardView.backgroundColor = .secondarySystemBackground
        cardView.layer.cornerRadius = 12
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.1
        cardView.layer.shadowOffset = CGSize(width: 0, height: 2)
        cardView.layer.shadowRadius = 4
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])

        // Title
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.numberOfLines = 2
        titleLabel.textAlignment = .left

        // Action buttons
        configureIconButton(actionButton, systemName: "arrow.down.circle")
        actionButton.addTarget(self, action: #selector(onActionTap), for: .touchUpInside)

        configureIconButton(pauseResumeButton, systemName: "pause.fill")
        pauseResumeButton.addTarget(self, action: #selector(onPauseResumeTap), for: .touchUpInside)
        pauseResumeButton.isHidden = true

        let buttonStack = UIStackView(arrangedSubviews: [actionButton, pauseResumeButton])
        buttonStack.axis = .horizontal
        buttonStack.alignment = .center
        buttonStack.spacing = 24
        buttonStack.distribution = .equalCentering

        // Progress
        progressView.progress = 0.0
        progressView.trackTintColor = UIColor.systemGray5
        progressView.tintColor = UIColor.systemBlue

        progressLabel.font = .systemFont(ofSize: 13, weight: .medium)
        progressLabel.textColor = .secondaryLabel
        progressLabel.text = "0%"

        let progressStack = UIStackView(arrangedSubviews: [progressView, progressLabel])
        progressStack.axis = .horizontal
        progressStack.spacing = 8
        progressStack.alignment = .center

        // Main vertical stack
        let mainStack = UIStackView(arrangedSubviews: [titleLabel, buttonStack, progressStack])
        mainStack.axis = .vertical
        mainStack.spacing = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            mainStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            mainStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),

            progressView.heightAnchor.constraint(equalToConstant: 4)
        ])
    }

    private func configureIconButton(_ button: UIButton, systemName: String) {
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        button.setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
        button.tintColor = .systemBlue
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 36),
            button.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    // MARK: - Button Actions
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
    }

    // MARK: - Configure
    func configure(title: String,
                   progress: Float,
                   downloading: Bool = false,
                   failed: Bool = false,
                   paused: Bool = false,
                   downloaded: Bool = false) {
        titleLabel.text = title
        progressView.progress = progress
        progressLabel.text = "\(Int(progress * 100))%"
        isDownloading = downloading
        hasFailed = failed
        isPaused = paused
        isDownloaded = downloaded

        // Always make sure actionButton is visible unless paused/downloading
        actionButton.isHidden = false
        updateUI()
    }


    private func updateUI() {
        if isDownloaded {
            // Show "open file" option
            actionButton.setImage(UIImage(systemName: "folder"), for: .normal)
            pauseResumeButton.isHidden = true

        } else if hasFailed {
            // Show retry
            actionButton.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
            pauseResumeButton.isHidden = true

        } else if isPaused {
            // Paused: Show resume button, hide "Download"
            actionButton.isHidden = true
            pauseResumeButton.isHidden = false
            pauseResumeButton.setImage(UIImage(systemName: "play.fill"), for: .normal)

        } else if isDownloading {
            // Actively downloading
            actionButton.isHidden = true
            pauseResumeButton.isHidden = false
            pauseResumeButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)

        } else {
            // Not started
            actionButton.isHidden = false
            actionButton.setImage(UIImage(systemName: "arrow.down.circle"), for: .normal)
            pauseResumeButton.isHidden = true
            progressView.progress = 0
            progressLabel.text = "0%"
        }
    }
    func updateProgress(_ progress: Float) {
        progressView.setProgress(progress, animated: true)
        progressLabel.text = "\(Int(progress * 100))%"
    }

}
