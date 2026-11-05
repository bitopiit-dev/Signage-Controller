import 'package:flutter/material.dart';

class ConicalGradient extends Gradient {
  const ConicalGradient({
    required super.colors,
    super.stops,
    super.transform,
  });

  @override
  Shader createShader(Rect rect, {TextDirection? textDirection}) {
    return SweepGradient(
      colors: colors,
      stops: stops,
      transform: transform,
    ).createShader(rect, textDirection: textDirection);
  }

  @override
  Gradient scale(double factor) => this;

  @override
  Gradient withOpacity(double opacity) => this;
}

class VintageCDPlayer extends StatefulWidget {
  final bool isPlaying;
  const VintageCDPlayer({required this.isPlaying, super.key});

  @override
  State<VintageCDPlayer> createState() => _VintageCDPlayerState();
}

class _VintageCDPlayerState extends State<VintageCDPlayer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 3));
    if (widget.isPlaying) _controller.repeat();
  }

  @override
  void didUpdateWidget(VintageCDPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: RotationTransition(
        turns: _controller,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: ConicalGradient(
                  colors: [
                    Colors.grey[800]!,
                    Colors.grey[400]!,
                    Colors.grey[800]!,
                    Colors.grey[400]!,
                    Colors.grey[800]!,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 20,
                    spreadRadius: 5,
                  )
                ],
              ),
            ),
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black,
              ),
              child: const Center(child: Icon(Icons.music_note, color: Colors.white, size: 30)),
            ),
            Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
