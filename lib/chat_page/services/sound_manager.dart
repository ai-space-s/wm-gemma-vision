// lib/chat_page/services/sound_manager.dart
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

class SoundManager {
  static final SoundManager _instance = SoundManager._internal();
  static SoundManager get instance => _instance;

  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioPlayer _loadingPlayer = AudioPlayer();
  final AudioPlayer _dictationPlayer = AudioPlayer();
  bool _isLoadingPlaying = false;

  SoundManager._internal();

  /// Play woosh sound for message sending (increased volume)
  Future<void> playWoosh() async {
    try {
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.play(AssetSource('woosh.mp3'));
    } catch (e) {
      print('Error playing woosh sound: $e');
      // Fallback to system sound
      await SystemSound.play(SystemSoundType.click);
    }
  }

  /// Play dictation start sound from file
  Future<void> playDictationStart() async {
    try {
      await _dictationPlayer.setVolume(1.0); // Max volume for better audibility
      await _dictationPlayer.play(AssetSource('dictation_start.mp3'));
      print('Playing dictation start sound');
    } catch (e) {
      print('Error playing dictation start sound: $e');
      // Fallback to system sound + haptic
      await HapticFeedback.lightImpact();
      await SystemSound.play(SystemSoundType.click);
    }
  }

  /// Play dictation stop sound from file
  Future<void> playDictationStop() async {
    try {
      await _dictationPlayer.setVolume(1.0); // Max volume for better audibility
      await _dictationPlayer.play(AssetSource('dictation_stop.mp3'));
      print('Playing dictation stop sound');
    } catch (e) {
      print('Error playing dictation stop sound: $e');
      // Fallback to system sound + haptic
      await HapticFeedback.mediumImpact();
      await SystemSound.play(SystemSoundType.click);
    }
  }

  /// Play loading sound with better volume
  Future<void> playLoading() async {
    if (_isLoadingPlaying) return;

    try {
      _isLoadingPlaying = true;
      await _loadingPlayer.setReleaseMode(ReleaseMode.loop);
      await _loadingPlayer.setVolume(0.8);
      await _loadingPlayer.play(AssetSource('loading.mp3'));
    } catch (e) {
      _isLoadingPlaying = false;
      print('Error playing loading sound: $e');
    }
  }

  Future<void> stopLoading() async {
    if (!_isLoadingPlaying) return;

    try {
      _isLoadingPlaying = false;
      await _loadingPlayer.stop();
    } catch (e) {
      print('Error stopping loading sound: $e');
    }
  }

  Future<void> pauseLoading() async {
    if (!_isLoadingPlaying) return;

    try {
      await _loadingPlayer.pause();
    } catch (e) {
      print('Error pausing loading sound: $e');
    }
  }

  Future<void> resumeLoading() async {
    if (!_isLoadingPlaying) return;

    try {
      await _loadingPlayer.resume();
    } catch (e) {
      print('Error resuming loading sound: $e');
    }
  }

  void dispose() {
    _audioPlayer.dispose();
    _loadingPlayer.dispose();
    _dictationPlayer.dispose();
  }
}
