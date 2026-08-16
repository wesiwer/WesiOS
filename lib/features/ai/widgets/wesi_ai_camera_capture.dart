import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../models/wesi_ai_attachment.dart';

class WesiAiCameraCaptureScreen extends StatefulWidget {
  const WesiAiCameraCaptureScreen({super.key});

  @override
  State<WesiAiCameraCaptureScreen> createState() => _WesiAiCameraCaptureScreenState();
}

class _WesiAiCameraCaptureScreenState extends State<WesiAiCameraCaptureScreen>
    with WidgetsBindingObserver {
  List<CameraDescription> _cameras = const <CameraDescription>[];
  CameraController? _controller;
  int _cameraIndex = 0;
  bool _loading = true;
  bool _capturing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  bool get _supportedPlatform => Platform.isAndroid || Platform.isIOS;

  Future<void> _initialize({int? cameraIndex}) async {
    if (!_supportedPlatform) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Встроенная камера доступна на Android и iOS';
        });
      }
      return;
    }
    try {
      final cameras = _cameras.isEmpty ? await availableCameras() : _cameras;
      if (cameras.isEmpty) throw CameraException('NoCamera', 'Камера не найдена');
      final index = (cameraIndex ?? _cameraIndex).clamp(0, cameras.length - 1);
      final previous = _controller;
      _controller = null;
      await previous?.dispose();
      final controller = CameraController(
        cameras[index],
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameras = cameras;
        _cameraIndex = index;
        _controller = controller;
        _loading = false;
        _error = null;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = switch (e.code) {
          'CameraAccessDenied' => 'Доступ к камере запрещён. Разрешите камеру в настройках устройства.',
          'CameraAccessDeniedWithoutPrompt' => 'Доступ к камере отключён в настройках устройства.',
          'CameraAccessRestricted' => 'Доступ к камере ограничен системой.',
          _ => e.description ?? 'Не удалось открыть камеру',
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось открыть камеру';
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _controller = null;
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      setState(() => _loading = true);
      _initialize(cameraIndex: _cameraIndex);
    }
  }

  Future<void> _switchCamera() async {
    if (_capturing || _cameras.length < 2) return;
    setState(() => _loading = true);
    await _initialize(cameraIndex: (_cameraIndex + 1) % _cameras.length);
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    try {
      final shot = await controller.takePicture();
      final bytes = await shot.readAsBytes();
      final attachment = WesiAiAttachment.fromBytes(
        name: 'camera_${DateTime.now().millisecondsSinceEpoch}.jpg',
        bytes: bytes,
        mimeType: 'image/jpeg',
      );
      if (!mounted) return;
      Navigator.of(context).pop<WesiAiAttachment>(attachment);
    } on CameraException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.description ?? 'Не удалось сделать снимок')),
      );
      setState(() => _capturing = false);
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      setState(() => _capturing = false);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сделать снимок')),
      );
      setState(() => _capturing = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null && controller.value.isInitialized)
            LayoutBuilder(
              builder: (context, constraints) {
                final preview = controller.value.previewSize;
                return ClipRect(
                  child: SizedBox.expand(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: preview?.height ?? constraints.maxWidth,
                        height: preview?.width ?? constraints.maxHeight,
                        child: CameraPreview(controller),
                      ),
                    ),
                  ),
                );
              },
            )
          else if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error ?? 'Камера недоступна',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  top: 12,
                  left: 12,
                  child: IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: Colors.black54),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ),
                if (_cameras.length > 1)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: IconButton.filled(
                      style: IconButton.styleFrom(backgroundColor: Colors.black54),
                      onPressed: _loading || _capturing ? null : _switchCamera,
                      icon: const Icon(Icons.cameraswitch_outlined, color: Colors.white),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 30,
                  child: Center(
                    child: GestureDetector(
                      onTap: controller != null && !_loading && !_capturing ? _takePicture : null,
                      child: Container(
                        width: 82,
                        height: 82,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 5),
                          color: _capturing ? Colors.white38 : Colors.white24,
                          boxShadow: const [
                            BoxShadow(color: Colors.black45, blurRadius: 18),
                          ],
                        ),
                        child: _capturing
                            ? const Padding(
                                padding: EdgeInsets.all(23),
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 3,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
