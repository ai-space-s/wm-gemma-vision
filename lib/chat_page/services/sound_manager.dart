// lib/chat_page/services/sound_manager.dart
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../app_settings.dart';

/// Centralized audio management for app sounds with fallback handling
class SoundManager {
  static final SoundManager _instance = SoundManager._internal();
  static SoundManager get instance => _instance;

  final AudioPlayer _audioPlayer = AudioPlayer(); // General sounds
  final AudioPlayer _loadingPlayer = AudioPlayer(); // Loading loop
  final AudioPlayer _dictationPlayer = AudioPlayer(); // Speech feedback
  bool _isLoadingPlaying = false;

  SoundManager._internal();

  bool get _earconsEnabled => AppSettings.instance.earconsEnabled;
  bool get _hapticsEnabled => AppSettings.instance.hapticsEnabled;

  Future<void> playConnectionCheck() async {
    try {
      // [수정] 호환성을 위해 vibrate 사용
      await HapticFeedback.vibrate();

      if (!_earconsEnabled) return;
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.play(AssetSource('woosh.mp3'));
    } catch (e) {
      debugPrint('Error playing connection check: $e');
    }
  }

  /// [수정] 햅틱 피드백을 lightImpact/mediumImpact 대신 vibrate로 변경하여 확실한 피드백 제공
  Future<void> playWoosh() async {
    try {
      if (_hapticsEnabled) {
        // [수정] 일부 기기에서 Impact 계열 피드백이 작동하지 않는 문제 해결을 위해 표준 진동 사용
        await HapticFeedback.vibrate();
      }
      if (!_earconsEnabled) return;
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.play(AssetSource('woosh.mp3'));
    } catch (e) {
      debugPrint('Error playing woosh sound: $e');
      await SystemSound.play(SystemSoundType.click);
    }
  }

  Future<void> playDictationStart() async {
    try {
      if (_hapticsEnabled) {
        // [수정] vibrate로 통일
        await HapticFeedback.vibrate();
      }
      if (!_earconsEnabled) return;
      await _dictationPlayer.setVolume(1.0);
      await _dictationPlayer.play(AssetSource('dictation_start.mp3'));
    } catch (e) {
      // Fallback
      if (_hapticsEnabled) await HapticFeedback.vibrate();
    }
  }

  Future<void> playDictationStop() async {
    try {
      if (_hapticsEnabled) {
        // [수정] vibrate로 통일
        await HapticFeedback.vibrate();
      }
      if (!_earconsEnabled) return;
      await _dictationPlayer.setVolume(1.0);
      await _dictationPlayer.play(AssetSource('dictation_stop.mp3'));
    } catch (e) {
      if (_hapticsEnabled) await HapticFeedback.vibrate();
    }
  }

  Future<void> playLoading() async {
    if (_isLoadingPlaying) return;

    try {
      _isLoadingPlaying = true;
      if (!_earconsEnabled) return;
      await _loadingPlayer.setReleaseMode(ReleaseMode.loop);
      await _loadingPlayer.setVolume(0.8);
      await _loadingPlayer.play(AssetSource('loading.mp3'));
    } catch (e) {
      _isLoadingPlaying = false;
      debugPrint('Error playing loading sound: $e');
    }
  }

  Future<void> stopLoading() async {
    if (!_isLoadingPlaying) return;

    try {
      _isLoadingPlaying = false;
      if (!_earconsEnabled) return;
      await _loadingPlayer.stop();
    } catch (e) {
      debugPrint('Error stopping loading sound: $e');
    }
  }

  Future<void> pauseLoading() async {
    if (!_isLoadingPlaying) return;
    try {
      if (!_earconsEnabled) return;
      await _loadingPlayer.pause();
    } catch (e) {
      debugPrint('Error pausing loading sound: $e');
    }
  }

  Future<void> resumeLoading() async {
    if (!_isLoadingPlaying) return;
    try {
      if (!_earconsEnabled) return;
      await _loadingPlayer.resume();
    } catch (e) {
      debugPrint('Error resuming loading sound: $e');
    }
  }

  void dispose() {
    _audioPlayer.dispose();
    _loadingPlayer.dispose();
    _dictationPlayer.dispose();
  }
}
