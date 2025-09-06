# VideoDownloader

A **feature-rich iOS video downloader app** built in Swift, demonstrating modern background download techniques, persistence, and UI feedback.

##  Features

- **Background Downloads**  
  Uses `URLSession` background sessions to enable downloads that continue even if the app is closed.

- **Pause / Resume / Retry Support**  
  Download state is maintained via resume data, allowing for pausing and graceful recovery.

- **Progress Tracking UI**  
  Download progress shown per video with real-time updates in the UI.

- **Download List Screen**  
  Comes with a “Downloaded Videos” list that:
  - Shows each video's title
  - Displays days remaining until expiry (or "Expired")
  - Allows deleting videos

- **Expiry Management**  
  Automatically expires videos after 30 days; expired videos are cleaned up and removed.

- **Error Handling**  
  Handles storage limits, timeouts, network loss — offering retry options and notifications.

- **Persistence**  
  State persists across app launches using:
  - **UserDefaults** for in-progress tracking
  - **Core Data** for downloaded history

- **Local Notifications**  
  Alerts the user when a download completes, with options to go directly to the download list.

##  Getting Started

1. Clone the repo:
   ```bash
   git clone https://github.com/KeerthikaChokkalingam/VideoDownloader.git
