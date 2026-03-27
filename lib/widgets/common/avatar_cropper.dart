import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:math' as math;
import 'package:path_provider/path_provider.dart';
import '../../styles/app_styles.dart';

class AvatarCropper extends StatefulWidget {
  final File? imageFile;

  const AvatarCropper({super.key, this.imageFile});

  static Future<File?> show(BuildContext context, File imageFile) async {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AvatarCropper(imageFile: imageFile),
      ),
    );
  }

  @override
  State<AvatarCropper> createState() => _AvatarCropperState();
}

class _AvatarCropperState extends State<AvatarCropper> {
  double _scale = 1.0;
  double _previousScale = 1.0;
  Offset _offset = Offset.zero;
  Offset _previousOffset = Offset.zero;

  double _rotation = 0.0;
  bool _flipHorizontal = false;
  bool _flipVertical = false;

  final GlobalKey _repaintBoundaryKey = GlobalKey();
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Редактирование', style: AppStyles.titleLarge),
        actions: [
          IconButton(
            icon: _isSaving 
                ? const SizedBox(
                    width: 20, 
                    height: 20, 
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.check, color: Colors.white),
            onPressed: _isSaving ? null : _saveCroppedImage,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double cropSize = math.min(constraints.maxWidth, constraints.maxHeight) * 0.9;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Base background
                    Container(color: Colors.black),
                    
                    // The capture area
                    RepaintBoundary(
                      key: _repaintBoundaryKey,
                      child: Container(
                        width: cropSize,
                        height: cropSize,
                        clipBehavior: Clip.hardEdge,
                        decoration: const BoxDecoration(
                          color: Colors.black,
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Transform.translate(
                              offset: _offset,
                              child: Transform.scale(
                                scale: _scale,
                                child: Transform(
                                  alignment: Alignment.center,
                                  transform: Matrix4.rotationZ(_rotation)
                                    ..rotateY(_flipHorizontal ? math.pi : 0.0)
                                    ..rotateX(_flipVertical ? math.pi : 0.0),
                                  child: widget.imageFile != null
                                      ? Image.file(widget.imageFile!, fit: BoxFit.contain)
                                      : Image.asset('assets/images/medved.png', fit: BoxFit.contain),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    // Overlay with dark mask and white circle border
                    IgnorePointer(
                      child: CustomPaint(
                        size: Size(constraints.maxWidth, constraints.maxHeight),
                        painter: CircleOverlayPainter(cropSize: cropSize),
                      ),
                    ),
                    
                    // Full-screen gesture detector so dragging is smooth anywhere
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onScaleStart: (details) {
                          _previousScale = _scale;
                          _previousOffset = details.focalPoint;
                        },
                        onScaleUpdate: (details) {
                          setState(() {
                            _scale = math.max(0.2, _previousScale * details.scale);
                            
                            // Prevent dragging out of bounds too far
                            Offset newOffset = _offset + (details.focalPoint - _previousOffset);
                            double limit = cropSize * _scale; 
                            _offset = Offset(
                              newOffset.dx.clamp(-limit, limit),
                              newOffset.dy.clamp(-limit, limit),
                            );
                            _previousOffset = details.focalPoint;
                          });
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // Toolbar
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            color: const Color(0xFF161616),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildToolButton(
                  icon: Icons.rotate_left,
                  onTap: () => setState(() => _rotation -= math.pi / 2),
                ),
                _buildToolButton(
                  icon: Icons.rotate_right,
                  onTap: () => setState(() => _rotation += math.pi / 2),
                ),
                _buildToolButton(
                  icon: Icons.flip,
                  onTap: () => setState(() => _flipHorizontal = !_flipHorizontal),
                ),
                _buildToolButton(
                  icon: Icons.flip_camera_android,
                  onTap: () => setState(() => _flipVertical = !_flipVertical),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveCroppedImage() async {
    if (widget.imageFile == null) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // Capture the exact visible area in the screen boundary Box
      final boundary = _repaintBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Boundary not found');

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Failed to get byte data');

      final Uint8List pngBytes = byteData.buffer.asUint8List();
      
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/cropped_avatar_${DateTime.now().millisecondsSinceEpoch}.png');
      await tempFile.writeAsBytes(pngBytes);
      
      if (mounted) {
        Navigator.of(context).pop(tempFile);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Widget _buildToolButton({required IconData icon, required VoidCallback onTap}) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: Colors.white, size: 28),
      padding: const EdgeInsets.all(12),
      constraints: const BoxConstraints(),
    );
  }
}

class CircleOverlayPainter extends CustomPainter {
  final double cropSize;

  CircleOverlayPainter({required this.cropSize});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = cropSize / 2;

    final path = Path()
      ..addRect(rect)
      ..addOval(Rect.fromCircle(center: center, radius: radius))
      ..fillType = PathFillType.evenOdd;

    final paintMask = Paint()
      ..color = Colors.black.withOpacity(0.7)
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paintMask);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white70
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CircleOverlayPainter oldDelegate) {
    return oldDelegate.cropSize != cropSize;
  }
}
