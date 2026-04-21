// lib/download_page/models/enums.dart

/// Enum representing the current status of the download process.
enum DownloadStatus {
  notStarted,
  checkingAccess,
  authenticating,
  awaitingLicenseAcceptance,
  downloading,
  copying, // Assets에서 복사 중인 상태
  paused,
  completed,
  failed,
}

/// Enum representing the status of authentication tokens.
enum TokenStatus {
  notStored,
  valid,
  expired,
}

/// Enum to identify download target
enum DownloadTarget {
  mainModel,
}
