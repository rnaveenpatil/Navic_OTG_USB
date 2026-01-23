import 'package:flutter/material.dart';
import 'package:navic_ss/screens/emergency.dart';
import 'package:video_player/video_player.dart';

class VideoTransitionScreen extends StatefulWidget {
  final String videoPath;
  final Widget nextScreen;
  final Duration delayAfterVideo;

  const VideoTransitionScreen({
    Key? key,
    required this.videoPath,
    required this.nextScreen,
    this.delayAfterVideo = const Duration(seconds: 1),
  }) : super(key: key);

  @override
  State<VideoTransitionScreen> createState() => _VideoTransitionScreenState();
}

class _VideoTransitionScreenState extends State<VideoTransitionScreen> {
  late VideoPlayerController _controller;
  bool _isVideoInitialized = false;
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      _controller = VideoPlayerController.asset('assets/emergency.mp4');
      
      await _controller.initialize().then((_) {
        setState(() {
          _isVideoInitialized = true;
        });
        
        _controller.play();
        
        // Navigate when video completes
        _controller.addListener(() {
          if (_controller.value.position >= _controller.value.duration && !_isNavigating) {
            _navigateToNext();
          }
        });
        
        // Fallback navigation
        Future.delayed(_controller.value.duration + widget.delayAfterVideo, _navigateToNext);
      });
    } catch (e) {
      print('Error loading transition video: $e');
      Future.delayed(const Duration(seconds: 2), _navigateToNext);
    }
  }

  void _navigateToNext() {
    if (!_isNavigating && mounted) {
      _isNavigating = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => EmergencyPage()),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: _isVideoInitialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
            : const CircularProgressIndicator(
                color: Colors.white,
              ),
      ),
    );
  }
}