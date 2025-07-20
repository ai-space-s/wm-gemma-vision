// lib/chat_page/services/sound_manager.dart
import 'package:audioplayers/audioplayers.dart';

class SoundManager {
  static final SoundManager _instance = SoundManager._internal();
  static SoundManager get instance => _instance;

  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioPlayer _loadingPlayer = AudioPlayer();
  bool _isLoadingPlaying = false;

  SoundManager._internal();

  Future<void> playWoosh() async {
    try {
      await _audioPlayer.play(AssetSource('woosh.mp3'));
    } catch (e) {
      print('Error playing woosh sound: $e');
    }
  }

  Future<void> playLoading() async {
    if (_isLoadingPlaying) return;

    try {
      _isLoadingPlaying = true;
      await _loadingPlayer.setReleaseMode(ReleaseMode.loop);
      await _loadingPlayer.setVolume(0.7);
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
  }
}
