// Dart imports:
import 'dart:io';

// Package imports:
import 'package:injectable/injectable.dart';
import 'package:wakelock/wakelock.dart';

// Project imports:
import 'package:waterbus_sdk/helpers/replaykit/replaykit_helper.dart';
import 'package:waterbus_sdk/interfaces/webrtc_interface.dart';
import 'package:waterbus_sdk/method_channels/replaykit.dart';
import 'package:waterbus_sdk/models/index.dart';

@Singleton()
class SdkCore {
  final WaterbusWebRTCManager _rtcManager;
  final ReplayKitChannel _replayKitChannel;
  SdkCore(
    this._rtcManager,
    this._replayKitChannel,
  );

  Future<void> joinRoom({
    required String roomId,
    required int participantId,
    required Function(CallbackPayload) onNewEvent,
  }) async {
    Wakelock.enable();

    await _rtcManager.joinRoom(
      roomId: roomId,
      participantId: participantId,
    );

    _rtcManager.notifyChanged.listen((event) {
      onNewEvent(event);
    });
  }

  Future<void> leaveRoom() async {
    await _rtcManager.dispose();
    Wakelock.disable();
  }

  Future<void> prepareMedia() async {
    await _rtcManager.prepareMedia();
  }

  Future<void> changeCallSettings(CallSetting setting) async {
    await _rtcManager.applyCallSettings(setting);
  }

  Future<void> toggleVideo() async {
    await _rtcManager.toggleVideo();
  }

  Future<void> toggleAudio() async {
    await _rtcManager.toggleAudio();
  }

  Future<void> startScreenSharing() async {
    if (Platform.isIOS) {
      ReplayKitHelper().openReplayKit();
      _replayKitChannel.startReplayKit();
      _replayKitChannel.listenEvents(_rtcManager);
    } else {
      await _rtcManager.startScreenSharing();
    }
  }

  Future<void> stopScreenSharing() async {
    if (Platform.isIOS) {
      ReplayKitHelper().openReplayKit();
    } else {
      await _rtcManager.stopScreenSharing();
    }
  }

  CallState get callState => _rtcManager.callState();
}
