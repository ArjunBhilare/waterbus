// Copyright 2023 LiveKit, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Flutter imports:
import 'package:flutter/foundation.dart';

class CodecStats {
  String? mimeType;
  num? payloadType;
  num? channels;
  num? clockRate;
}

// key stats for senders and receivers
class SenderStats extends CodecStats {
  SenderStats(this.streamId, this.timestamp);

  /// number of packets sent
  num? packetsSent;

  /// number of bytes sent
  num? bytesSent;

  /// jitter as perceived by remote
  num? jitter;

  /// packets reported lost by remote
  num? packetsLost;

  /// RTT reported by remote
  num? roundTripTime;

  /// ID of the outbound stream
  String streamId;

  String? encoderImplementation;

  num timestamp;
}

class AudioSenderStats extends SenderStats {
  AudioSenderStats(super.streamId, super.timestamp);
}

class VideoSenderStats extends SenderStats {
  VideoSenderStats(super.streamId, super.timestamp);

  num? firCount;

  num? pliCount;

  num? nackCount;

  String? rid;

  num? frameWidth;

  num? frameHeight;

  num? framesSent;

  num? framesPerSecond;

  // bandwidth, cpu, other, none
  String? qualityLimitationReason;

  num? qualityLimitationResolutionChanges;

  num? retransmittedPacketsSent;

  @override
  String toString() {
    return 'latency: ${(roundTripTime ?? 0) * 1000}ms | jitter: $jitter | packetsLost: $packetsLost';
  }

  String infoVideo() {
    return 'framesSent: $framesSent | frameHeight: $frameHeight | frameWidth: $frameWidth | framePerSecond: $framesPerSecond';
  }
}

class ReceiverStats extends CodecStats {
  ReceiverStats(this.streamId, this.timestamp);
  num? jitterBufferDelay;

  /// packets reported lost by remote
  num? packetsLost;

  /// number of packets sent
  num? packetsReceived;

  num? bytesReceived;

  String streamId;

  num? jitter;

  num timestamp;
}

class AudioReceiverStats extends ReceiverStats {
  AudioReceiverStats(super.streamId, super.timestamp);

  num? concealedSamples;

  num? concealmentEvents;

  num? silentConcealedSamples;

  num? silentConcealmentEvents;

  num? totalAudioEnergy;

  num? totalSamplesDuration;
}

class VideoReceiverStats extends ReceiverStats {
  VideoReceiverStats(super.streamId, super.timestamp);

  num? framesDecoded;

  num? framesDropped;

  num? framesReceived;

  num? framesPerSecond;

  num? frameWidth;

  num? frameHeight;

  num? firCount;

  num? pliCount;

  num? nackCount;

  String? decoderImplementation;
}

num computeBitrateForSenderStats(
  SenderStats currentStats,
  SenderStats? prevStats,
) {
  if (prevStats == null) {
    return 0;
  }
  num? bytesNow;
  num? bytesPrev;
  bytesNow = currentStats.bytesSent;
  bytesPrev = prevStats.bytesSent;
  if (bytesNow == null || bytesPrev == null) {
    return 0;
  }
  if (kIsWeb) {
    return ((bytesNow - bytesPrev) * 8) /
        (currentStats.timestamp - prevStats.timestamp);
  }

  return ((bytesNow - bytesPrev) * 8 * 1000) /
      (currentStats.timestamp - prevStats.timestamp);
}

num computeBitrateForReceiverStats(
  ReceiverStats currentStats,
  ReceiverStats? prevStats,
) {
  if (prevStats == null) {
    return 0;
  }
  num? bytesNow;
  num? bytesPrev;

  bytesNow = currentStats.bytesReceived;
  bytesPrev = prevStats.bytesReceived;

  if (bytesNow == null || bytesPrev == null) {
    return 0;
  }
  if (kIsWeb) {
    return ((bytesNow - bytesPrev) * 8) /
        (currentStats.timestamp - prevStats.timestamp);
  }

  return ((bytesNow - bytesPrev) * 8 * 1000) /
      (currentStats.timestamp - prevStats.timestamp);
}

num? getNumValFromReport(Map<dynamic, dynamic> values, String key) {
  if (values.containsKey(key)) {
    return (values[key] is String)
        ? num.tryParse(values[key])
        : values[key] as num;
  }
  return null;
}

String? getStringValFromReport(Map<dynamic, dynamic> values, String key) {
  if (values.containsKey(key)) {
    return values[key] as String;
  }
  return null;
}