// Dart imports:
import 'dart:async';
import 'dart:io';

// Package imports:
import 'package:injectable/injectable.dart';
import 'package:sdp_transform/sdp_transform.dart';

// Project imports:
import 'package:waterbus_sdk/constants/webrtc_configurations.dart';
import 'package:waterbus_sdk/flutter_waterbus_sdk.dart';
import 'package:waterbus_sdk/helpers/extensions/sdp_extensions.dart';
import 'package:waterbus_sdk/interfaces/socket_emiter_interface.dart';
import 'package:waterbus_sdk/interfaces/webrtc_interface.dart';
import 'package:waterbus_sdk/method_channels/foreground.dart';
import 'package:waterbus_sdk/method_channels/replaykit.dart';

@LazySingleton(as: WaterbusWebRTCManager)
class WaterbusWebRTCManagerIpml extends WaterbusWebRTCManager {
  final SocketEmiter _socketEmiter;
  final ForegroundService _foregroundService;
  final ReplayKitChannel _replayKitChannel;
  WaterbusWebRTCManagerIpml(
    this._socketEmiter,
    this._foregroundService,
    this._replayKitChannel,
  );

  String? _roomId;
  MediaStream? _localStream;
  ParticipantSFU? _mParticipant;
  bool _flagPublisherCanAddCandidate = false;
  CallSetting _callSetting = CallSetting();
  final Map<String, ParticipantSFU> _subscribers = {};
  final Map<String, List<RTCIceCandidate>> _queueRemoteSubCandidates = {};
  final List<RTCIceCandidate> _queuePublisherCandidates = [];
  // ignore: close_sinks
  final StreamController<CallbackPayload> _notifyChanged =
      StreamController<CallbackPayload>.broadcast();

  @override
  Future<void> prepareMedia() async {
    await _prepareMedia();
  }

  @override
  Future<void> startScreenSharing() async {
    try {
      if (_mParticipant == null) return;

      if (_mParticipant!.isVideoEnabled) {
        await toggleVideo(forceValue: false, ignoreUpdateValue: true);
      }

      if (Platform.isAndroid) {
        await _foregroundService.startForegroundService();
      }

      final MediaStream displayStream = await _getDisplayMedia();

      if (displayStream.getVideoTracks().isEmpty) return;

      await _replaceVideoTrack(displayStream.getVideoTracks().first);

      _mParticipant?.isSharingScreen = true;

      _notify(CallbackEvents.shouldBeUpdateState);
      _socketEmiter.setScreenSharing(true);
    } catch (e) {
      stopScreenSharing();
    }
  }

  @override
  Future<void> stopScreenSharing({bool stayInRoom = true}) async {
    _mParticipant?.isSharingScreen = false;

    if (_mParticipant == null) return;

    if (stayInRoom && (_localStream?.getVideoTracks().isNotEmpty ?? false)) {
      await _replaceVideoTrack(_localStream!.getVideoTracks().first);

      if (_mParticipant!.isVideoEnabled) {
        await toggleVideo(forceValue: true, ignoreUpdateValue: true);
      }
    }

    if (Platform.isAndroid) {
      await _foregroundService.stopForegroundService();
    }

    _mParticipant?.isSharingScreen = false;

    if (stayInRoom) {
      _notify(CallbackEvents.shouldBeUpdateState);
      _socketEmiter.setScreenSharing(false);
    } else {
      _replayKitChannel.closeReplayKit();
    }
  }

  @override
  Future<void> joinRoom({
    required String roomId,
    required int participantId,
  }) async {
    await _prepareMedia();

    if (_mParticipant?.peerConnection == null) return;

    _roomId = roomId;

    final RTCPeerConnection peerConnection = _mParticipant!.peerConnection;

    peerConnection.onIceCandidate = (candidate) {
      if (_flagPublisherCanAddCandidate) {
        _socketEmiter.sendBroadcastCandidate(candidate);
      } else {
        _queuePublisherCandidates.add(candidate);
      }
    };

    _localStream?.getTracks().forEach((track) {
      peerConnection.addTrack(track, _localStream!);
    });

    peerConnection.onRenegotiationNeeded = () async {
      if ((await peerConnection.getRemoteDescription()) != null) return;

      String sdp = await _createOffer(peerConnection);

      sdp = sdp.enableAudioDTX().setPreferredCodec(
            codec: _callSetting.preferedCodec,
          );

      final RTCSessionDescription description = RTCSessionDescription(
        sdp,
        DescriptionType.offer.type,
      );

      await peerConnection.setLocalDescription(description);

      _socketEmiter.establishBroadcast(
        sdp: sdp,
        roomId: _roomId!,
        participantId: participantId.toString(),
        isVideoEnabled: _mParticipant?.isVideoEnabled ?? false,
        isAudioEnabled: _mParticipant?.isAudioEnabled ?? false,
      );
    };
  }

  @override
  Future<void> subscribe(List<String> targetIds) async {
    for (final targetId in targetIds) {
      _makeConnectionReceive(targetId);
    }
  }

  @override
  Future<void> setPublisherRemoteSdp(String sdp) async {
    final RTCSessionDescription description = RTCSessionDescription(
      sdp,
      DescriptionType.answer.type,
    );

    await _mParticipant?.setRemoteDescription(description);

    for (final candidate in _queuePublisherCandidates) {
      _socketEmiter.sendBroadcastCandidate(candidate);
    }

    _queuePublisherCandidates.clear();
    _flagPublisherCanAddCandidate = true;
  }

  @override
  Future<void> setSubscriberRemoteSdp(
    String targetId,
    String sdp,
    bool videoEnabled,
    bool audioEnabled,
    bool isScreenSharing,
  ) async {
    if (_subscribers[targetId] != null) return;

    final RTCSessionDescription description = RTCSessionDescription(
      sdp,
      DescriptionType.offer.type,
    );

    await _answerSubscriber(
      targetId,
      description,
      videoEnabled,
      audioEnabled,
      isScreenSharing,
    );
  }

  @override
  Future<void> addPublisherCandidate(RTCIceCandidate candidate) async {
    await _mParticipant?.addCandidate(candidate);
  }

  @override
  Future<void> addSubscriberCandidate(
    String targetId,
    RTCIceCandidate candidate,
  ) async {
    if (_subscribers[targetId] != null) {
      await _subscribers[targetId]?.addCandidate(candidate);
    } else {
      final List<RTCIceCandidate> candidates =
          _queueRemoteSubCandidates[targetId] ?? [];

      candidates.add(candidate);

      _queueRemoteSubCandidates[targetId] = candidates;
    }
  }

  @override
  Future<void> newParticipant(String targetId) async {
    await _makeConnectionReceive(targetId);

    _notify(
      CallbackEvents.newParticipant,
      participantId: targetId,
    );
  }

  @override
  Future<void> participantHasLeft(String targetId) async {
    _notify(
      CallbackEvents.participantHasLeft,
      participantId: targetId,
    );

    await _subscribers[targetId]?.dispose();
    _subscribers.remove(targetId);
    _queueRemoteSubCandidates.remove(targetId);
  }

  // MARK: Control Media
  @override
  Future<void> applyCallSettings(CallSetting setting) async {
    if (_callSetting.videoQuality == setting.videoQuality) {
      _callSetting = setting;
      return;
    }

    _callSetting = setting;

    if (_localStream == null || _mParticipant == null) return;

    final MediaStream newStream = await _getUserMedia(onlyStream: true);

    await _replaceMediaStream(newStream);

    if (!(_mParticipant?.isVideoEnabled ?? true)) {
      await toggleVideo(forceValue: _mParticipant?.isVideoEnabled);
    }

    if (!(_mParticipant?.isAudioEnabled ?? true)) {
      await toggleAudio(forceValue: _mParticipant?.isAudioEnabled);
    }
  }

  @override
  Future<void> toggleVideo({
    bool? forceValue,
    bool ignoreUpdateValue = false,
  }) async {
    if (_mParticipant == null || _mParticipant!.isSharingScreen) return;

    final tracks = _localStream?.getVideoTracks() ?? [];

    if (_mParticipant!.isVideoEnabled) {
      for (final track in tracks) {
        track.enabled = forceValue ?? false;
      }
    } else {
      for (final track in tracks) {
        track.enabled = forceValue ?? true;
      }
    }

    if (ignoreUpdateValue) return;

    _mParticipant!.isVideoEnabled =
        forceValue ?? !_mParticipant!.isVideoEnabled;

    _notify(CallbackEvents.shouldBeUpdateState);

    if (_roomId != null) {
      _socketEmiter.setVideoEnabled(
        forceValue ?? _mParticipant!.isVideoEnabled,
      );
    }
  }

  @override
  Future<void> toggleAudio({bool? forceValue}) async {
    if (_mParticipant == null) return;

    final tracks = _localStream?.getAudioTracks() ?? [];

    if (_mParticipant!.isAudioEnabled) {
      for (final track in tracks) {
        track.enabled = forceValue ?? false;
      }
    } else {
      for (final track in tracks) {
        track.enabled = forceValue ?? true;
      }
    }

    _mParticipant!.isAudioEnabled =
        forceValue ?? !_mParticipant!.isAudioEnabled;

    _notify(CallbackEvents.shouldBeUpdateState);

    if (_roomId != null) {
      _socketEmiter.setAudioEnabled(
        forceValue ?? _mParticipant!.isAudioEnabled,
      );
    }
  }

  @override
  void setVideoEnabled({required String targetId, required bool isEnabled}) {
    _subscribers[targetId]?.isVideoEnabled = isEnabled;
    _notify(CallbackEvents.shouldBeUpdateState);
  }

  @override
  void setAudioEnabled({required String targetId, required bool isEnabled}) {
    _subscribers[targetId]?.isAudioEnabled = isEnabled;
    _notify(CallbackEvents.shouldBeUpdateState);
  }

  @override
  void setScreenSharing({required String targetId, required bool isSharing}) {
    _subscribers[targetId]?.isSharingScreen = isSharing;
    _notify(CallbackEvents.shouldBeUpdateState);
  }

  @override
  Future<void> dispose() async {
    if (_roomId != null) {
      _socketEmiter.leaveRoom(_roomId!);
    }

    _queuePublisherCandidates.clear();
    _queueRemoteSubCandidates.clear();
    _flagPublisherCanAddCandidate = false;

    for (final subscriber in _subscribers.values) {
      await subscriber.dispose();
    }
    _subscribers.clear();

    await stopScreenSharing(stayInRoom: false);
    await _localStream?.dispose();
    await _mParticipant?.dispose();
    _mParticipant = null;
    _localStream = null;
  }

  // MARK: Private methods
  Future<void> _prepareMedia() async {
    if (_mParticipant?.peerConnection != null) return;

    final RTCPeerConnection peerConnection = await _createPeerConnection(
      WebRTCConfigurations.offerPublisherSdpConstraints,
    );

    _mParticipant = ParticipantSFU(
      peerConnection: peerConnection,
      onChanged: () => _notify(CallbackEvents.shouldBeUpdateState),
      enableStats: true,
    );

    _localStream = await _getUserMedia();

    _mParticipant?.setSrcObject(_localStream!);
  }

  Future<MediaStream> _getUserMedia({bool onlyStream = false}) async {
    final MediaStream stream = await navigator.mediaDevices.getUserMedia(
      _callSetting.mediaConstraints,
    );

    if (onlyStream) return stream;

    await _toggleSpeakerPhone();

    if (_callSetting.isAudioMuted) {
      toggleAudio();
    }

    if (_callSetting.isVideoMuted) {
      toggleVideo();
    }

    return stream;
  }

  Future<MediaStream> _getDisplayMedia() async {
    final Map<String, dynamic> mediaConstraints = <String, dynamic>{
      'audio': false,
      'video': {
        'deviceId': 'broadcast',
        'frameRate': 15,
        'mandatory': {
          'minWidth': 1280,
          'minHeight': 720,
          'minFrameRate': 10,
        },
      },
    };

    final MediaStream stream = await navigator.mediaDevices.getDisplayMedia(
      mediaConstraints,
    );

    return stream;
  }

  Future<RTCPeerConnection> _createPeerConnection([
    Map<String, dynamic> constraints = const {},
  ]) async {
    final RTCPeerConnection pc = await createPeerConnection(
      WebRTCConfigurations.configurationWebRTC,
      constraints,
    );

    return pc;
  }

  Future<String> _createOffer(RTCPeerConnection peerConnection) async {
    final RTCSessionDescription description =
        await peerConnection.createOffer();
    final session = parse(description.sdp.toString());
    final String sdp = write(session, null);

    return sdp;
  }

  Future<String> _createAnswer(RTCPeerConnection peerConnection) async {
    final RTCSessionDescription description =
        await peerConnection.createAnswer();
    final session = parse(description.sdp.toString());
    final String sdp = write(session, null);

    return sdp;
  }

  Future<void> _makeConnectionReceive(String targetId) async {
    _socketEmiter.requestEstablishSubscriber(targetId: targetId);
  }

  Future<void> _answerSubscriber(
    String targetId,
    RTCSessionDescription remoteDescription,
    bool videoEnabled,
    bool audioEnabled,
    bool isScreenSharing,
  ) async {
    final RTCPeerConnection rtcPeerConnection = await _createPeerConnection(
      WebRTCConfigurations.offerSubscriberSdpConstraints,
    );

    _subscribers[targetId] = ParticipantSFU(
      peerConnection: rtcPeerConnection,
      onChanged: () => _notify(CallbackEvents.shouldBeUpdateState),
      isAudioEnabled: videoEnabled,
      isVideoEnabled: audioEnabled,
      isSharingScreen: isScreenSharing,
    );

    rtcPeerConnection.onAddStream = (stream) async {
      if (_subscribers[targetId] == null) return;

      _subscribers[targetId]?.setSrcObject(stream);
    };

    rtcPeerConnection.onIceCandidate = (candidate) {
      _socketEmiter.sendReceiverCandidate(
        candidate: candidate,
        targetId: targetId,
      );
    };

    rtcPeerConnection.setRemoteDescription(remoteDescription);

    final String sdp = await _createAnswer(rtcPeerConnection);
    final RTCSessionDescription description = RTCSessionDescription(
      sdp,
      DescriptionType.answer.type,
    );
    await rtcPeerConnection.setLocalDescription(description);

    _socketEmiter.answerEstablishSubscriber(targetId: targetId, sdp: sdp);

    // Process queue candidates from server
    final List<RTCIceCandidate> candidates =
        _queueRemoteSubCandidates[targetId] ?? [];

    for (final candidate in candidates) {
      addSubscriberCandidate(targetId, candidate);
    }
  }

  Future<void> _replaceMediaStream(MediaStream newStream) async {
    final senders = await _mParticipant!.peerConnection.getSenders();

    for (final sender in senders) {
      if (sender.track?.kind == 'audio') {
        sender.replaceTrack(newStream.getAudioTracks().first);
      } else if (sender.track?.kind == 'video') {
        sender.replaceTrack(newStream.getVideoTracks().first);
      }
    }

    _mParticipant?.setSrcObject(newStream);
    _localStream = newStream;
  }

  Future<void> _replaceVideoTrack(MediaStreamTrack track) async {
    final senders = await _mParticipant!.peerConnection.getSenders();

    for (final sender in senders) {
      if (sender.track?.kind == 'video') {
        sender.replaceTrack(track);
      }
    }
  }

  Future<void> _toggleSpeakerPhone() async {
    Helper.setSpeakerphoneOn(true);
  }

  void _notify(CallbackEvents event, {String? participantId}) {
    _notifyChanged.sink.add(
      CallbackPayload(
        event: event,
        callState: callState(),
        participantId: participantId,
      ),
    );
  }

  @override
  Stream<CallbackPayload> get notifyChanged => _notifyChanged.stream;

  @override
  CallState callState() {
    return CallState(
      mParticipant: _mParticipant,
      participants: _subscribers,
    );
  }
}
