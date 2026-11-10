import 'dart:io';

/// Resident set size of this process in bytes, or null where the platform
/// does not expose it (web).
int? currentRss() => ProcessInfo.currentRss;
