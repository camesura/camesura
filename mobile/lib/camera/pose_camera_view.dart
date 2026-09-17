import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../bridge/bridge_client.dart';
import '../bridge/bridge_settings.dart';
import '../pose/a_pose_conditions.dart';
import '../pose/a_pose_gate.dart';
import '../pose/a_pose_points.dart';
import '../pose/a_pose_stability_tracker.dart';
import '../pose/pose_skeleton_painter.dart';
import 'camera_image_converter.dart';

enum _CameraViewState { initializing, streaming, permissionDenied, unavailable }

// ML Kit recommends using the smallest input that still keeps the subject large
// enough for real-time pose detection. `high` made every inference unnecessarily
// expensive and reduced the rate at which the skeleton overlay could update.
const poseCameraResolutionPreset = ResolutionPreset.medium;

class PoseCameraView extends StatefulWidget {
  const PoseCameraView({
    super.key,
    this.client = const BridgeClient(),
    this.settings,
    this.onConditionsChanged,
  });

  final BridgeClient client;

  /// Bridgeの接続先。nullまたはhostが空の間はAポーズが成立しても送信しない。
  final BridgeSettings? settings;

  /// 監視画面の条件表示（全身/正面/直立/腕/静止）を更新するためのコールバック。
  final void Function(APoseConditions conditions, APoseGateState gateState)?
  onConditionsChanged;

  @override
  State<PoseCameraView> createState() => _PoseCameraViewState();
}

class _PoseCameraViewState extends State<PoseCameraView>
    with WidgetsBindingObserver {
  final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
  );

  CameraController? _controller;
  CameraDescription? _camera;
  PoseFrame? _poseFrame;
  _CameraViewState _state = _CameraViewState.initializing;
  String? _errorMessage;
  bool _isInitializing = false;
  bool _isProcessing = false;
  bool _isDisposed = false;
  int _cameraGeneration = 0;
  CameraLensDirection _lensDirection = CameraLensDirection.back;
  bool _hasFrontCamera = false;

  final Stopwatch _clock = Stopwatch()..start();
  final APoseStabilityTracker _stabilityTracker = APoseStabilityTracker();
  final APoseGate _gate = APoseGate();

  /// 正面を向けているか（静止を除く）。静止判定は検出精度の揺れで
  /// 成立しにくいため、枠の色は正面判定だけで「いけそうか」を示す。
  bool _looksGood = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initializeCamera());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      // Opening the system permission dialog also makes the app inactive.
      // Keep an in-flight first initialization alive so it can continue as
      // soon as the user grants access.
      if (_controller != null) {
        unawaited(_releaseCamera());
      }
    } else if (state == AppLifecycleState.resumed &&
        _controller == null &&
        !_isInitializing) {
      unawaited(_initializeCamera());
    }
  }

  Future<void> _initializeCamera() async {
    if (_isInitializing || _isDisposed) return;
    _isInitializing = true;
    final generation = ++_cameraGeneration;
    if (mounted) {
      setState(() {
        _state = _CameraViewState.initializing;
        _errorMessage = null;
        _poseFrame = null;
        _looksGood = false;
      });
    }

    CameraController? newController;
    try {
      final cameras = await availableCameras();
      _hasFrontCamera = cameras.any(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );
      final matchingCameras = cameras.where(
        (camera) => camera.lensDirection == _lensDirection,
      );
      if (matchingCameras.isEmpty) {
        throw CameraException(
          'CameraUnavailable',
          _lensDirection == CameraLensDirection.back
              ? '背面カメラが見つかりません'
              : '前面カメラが見つかりません',
        );
      }

      final camera = matchingCameras.first;
      newController = CameraController(
        camera,
        poseCameraResolutionPreset,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await newController.initialize();

      if (_isDisposed || generation != _cameraGeneration) {
        await _safeDispose(newController);
        return;
      }

      _camera = camera;
      _controller = newController;
      await newController.startImageStream(_processCameraImage);
      if (!mounted || generation != _cameraGeneration) return;
      setState(() => _state = _CameraViewState.streaming);
    } on CameraException catch (error) {
      if (_controller == newController) {
        _controller = null;
        _camera = null;
      }
      if (newController != null) {
        await _safeDispose(newController);
      }
      if (!mounted || generation != _cameraGeneration) return;
      final denied =
          error.code == 'CameraAccessDenied' ||
          error.code == 'CameraAccessDeniedWithoutPrompt' ||
          error.code == 'CameraAccessRestricted';
      setState(() {
        _state = denied
            ? _CameraViewState.permissionDenied
            : _CameraViewState.unavailable;
        _errorMessage = denied
            ? '骨格を確認するには、端末の設定でカメラを許可してください。'
            : 'カメラを起動できませんでした。';
      });
    } catch (_) {
      if (_controller == newController) {
        _controller = null;
        _camera = null;
      }
      if (newController != null) {
        await _safeDispose(newController);
      }
      if (!mounted || generation != _cameraGeneration) return;
      setState(() {
        _state = _CameraViewState.unavailable;
        _errorMessage = 'カメラを起動できませんでした。';
      });
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isProcessing || _isDisposed) return;
    final controller = _controller;
    final camera = _camera;
    if (controller == null || camera == null) return;

    final converted = convertCameraImage(
      image: image,
      camera: camera,
      deviceOrientation: controller.value.deviceOrientation,
    );
    if (converted == null) return;

    _isProcessing = true;
    try {
      final poses = await _poseDetector.processImage(converted.inputImage);
      if (!mounted || controller != _controller) return;
      final frame = poses.isEmpty
          ? null
          : PoseFrame(
              pose: poses.first,
              imageSize: converted.imageSize,
              rotation: converted.rotation,
              lensDirection: camera.lensDirection,
            );
      setState(() => _poseFrame = frame);
      _evaluateAPose(frame);
    } catch (_) {
      // A single malformed/dropped camera frame must not stop the stream.
    } finally {
      _isProcessing = false;
    }
  }

  /// 毎フレームAポーズ条件を評価し、2秒安定したらBridgeへYaw Resetを
  /// 要求する（camesura-spec.md 6.4）。
  void _evaluateAPose(PoseFrame? frame) {
    final timestamp = _clock.elapsed;
    final points = frame == null ? null : extractRequiredPoints(frame);
    final still = _stabilityTracker.addSample(
      timestamp: timestamp,
      points: points,
    );
    final conditions = evaluateAPoseConditions(
      points: points,
      imageSize: frame == null
          ? Size.zero
          : uprightImageSize(frame.imageSize, frame.rotation),
      still: still,
    );

    final action = _gate.update(
      allMet: conditions.allMet,
      timestamp: timestamp,
    );
    widget.onConditionsChanged?.call(conditions, _gate.state);

    final looksGood = conditions.frontFacing;
    if (looksGood != _looksGood && mounted) {
      setState(() => _looksGood = looksGood);
    }

    if (action == APoseGateAction.sendRequest) {
      unawaited(_sendAutoReset(points));
    }
  }

  Future<void> _sendAutoReset(PosePoints? points) async {
    final settings = widget.settings;
    final stableDuration =
        _gate.lastStableDuration ?? APoseThresholds.holdDuration;
    if (settings == null || settings.host.isEmpty) {
      _gate.completeSend(success: false);
      return;
    }
    var success = false;
    try {
      final response = await widget.client.requestReset(
        kind: ResetKind.yaw,
        host: settings.host,
        deviceId: settings.deviceId,
        pose: 'a_pose',
        stableMs: stableDuration.inMilliseconds,
        confidence: minRequiredLikelihood(points) ?? 0,
      );
      success = response.isOk;
    } on BridgeException {
      success = false;
    } finally {
      if (!_isDisposed) _gate.completeSend(success: success);
    }
  }

  Future<void> _switchCamera() async {
    if (_isInitializing || _isDisposed) return;
    _lensDirection = _lensDirection == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    await _releaseCamera();
    await _initializeCamera();
  }

  Future<void> _releaseCamera() async {
    _cameraGeneration++;
    final controller = _controller;
    _controller = null;
    _camera = null;
    _poseFrame = null;
    if (controller == null) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      await controller.dispose();
    } catch (_) {
      // The OS may already have released the camera while going inactive.
    }
  }

  Future<void> _safeDispose(CameraController controller) async {
    try {
      await controller.dispose();
    } catch (_) {
      // CameraX can fail disposal when initialization stopped before its
      // preview surface was ready. The original startup error is handled by
      // the caller and must still reach the UI.
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_releaseCamera());
    unawaited(_poseDetector.close().catchError((_) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showGoodBorder = _state == _CameraViewState.streaming && _looksGood;
    return AspectRatio(
      key: const Key('pose-camera-view'),
      aspectRatio: 4 / 5,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: showGoodBorder
                ? const Color(0xFF54E1A7)
                : Colors.transparent,
            width: 4,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: ColoredBox(
            color: const Color(0xFF061F28),
            child: switch (_state) {
              _CameraViewState.initializing => const _CameraMessage(
                icon: Icons.camera_alt_rounded,
                message: 'カメラを起動しています…',
                showProgress: true,
              ),
              _CameraViewState.permissionDenied ||
              _CameraViewState.unavailable => _CameraError(
                message: _errorMessage ?? 'カメラを起動できませんでした。',
                onRetry: _initializeCamera,
              ),
              _CameraViewState.streaming => _buildPreview(),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const _CameraMessage(
        icon: Icons.camera_alt_rounded,
        message: 'カメラを起動しています…',
        showProgress: true,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final previewSize = controller.value.previewSize;
        if (previewSize == null) return const SizedBox.shrink();

        final sourceSize = Size(previewSize.height, previewSize.width);
        final fitted = applyBoxFit(
          BoxFit.contain,
          sourceSize,
          constraints.biggest,
        );
        final previewRect = Alignment.center.inscribe(
          fitted.destination,
          Offset.zero & constraints.biggest,
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fromRect(
              rect: previewRect,
              child: RepaintBoundary(child: CameraPreview(controller)),
            ),
            if (_poseFrame case final frame?)
              Positioned.fromRect(
                rect: previewRect,
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(painter: PoseSkeletonPainter(frame)),
                  ),
                ),
              ),
            Positioned(
              top: 14,
              left: 14,
              child: _DetectionBadge(detected: _poseFrame != null),
            ),
            if (_hasFrontCamera)
              Positioned(
                top: 14,
                right: 14,
                child: _CameraSwitchButton(onPressed: _switchCamera),
              ),
            const Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Text(
                '全身が画面に入る位置に立ってください',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DetectionBadge extends StatelessWidget {
  const _DetectionBadge({required this.detected});

  final bool detected;

  @override
  Widget build(BuildContext context) {
    final color = detected ? const Color(0xFF54E1A7) : const Color(0xFFFFD166);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xD91A3138),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            detected
                ? Icons.accessibility_new_rounded
                : Icons.person_search_rounded,
            size: 17,
            color: color,
          ),
          const SizedBox(width: 7),
          Text(
            detected ? '骨格を検出しました' : '姿勢を探しています',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraSwitchButton extends StatelessWidget {
  const _CameraSwitchButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xD91A3138),
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onPressed,
        icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white),
        tooltip: 'カメラを切り替え',
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _CameraMessage(
      icon: Icons.no_photography_rounded,
      message: message,
      action: OutlinedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('もう一度試す'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFF54D7E1)),
        ),
      ),
    );
  }
}

class _CameraMessage extends StatelessWidget {
  const _CameraMessage({
    required this.icon,
    required this.message,
    this.action,
    this.showProgress = false,
  });

  final IconData icon;
  final String message;
  final Widget? action;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFF54D7E1), size: 52),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                height: 1.5,
              ),
            ),
            if (showProgress) ...[
              const SizedBox(height: 18),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Color(0xFF54E1A7),
                ),
              ),
            ],
            if (action case final action?) ...[
              const SizedBox(height: 18),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
