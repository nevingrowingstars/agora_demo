import 'dart:convert';
import 'dart:typed_data';

enum SequencedMessageType {
  data,
  ack,
  nack,
  batch,
}

/// A model for a single data payload, used inside a batch message.
class DataPayload {
  final int sequence;
  final Uint8List data;

  DataPayload({required this.sequence, required this.data});

  Map<String, dynamic> toJson() => {
        'sequence': sequence,
        'payload': base64Encode(data),
      };

  factory DataPayload.fromJson(Map<String, dynamic> json) => DataPayload(
        sequence: json['sequence'],
        data: base64Decode(json['payload']),
      );
}

/// A unified message model for the reliable data channel.
class SequencedMessage {
  final SequencedMessageType type;

  // Used for 'data' type
  final int? sequence;
  final Uint8List? payload;

  // Used for 'ack' type
  final int? ackSequence;

  // Used for 'nack' type
  final int? nackFromSequence;

  // Used for 'batch' type
  final List<DataPayload>? batchPayload;

  // --- NEW FIELDS FOR CHUNKING ---
  final String?
      chunkId; // A unique ID for all chunks of a single large message.
  final int? chunkIndex; // The order of this chunk (0, 1, 2...).
  final int? chunkTotal; // The total number of chunks for this message.

  // Private constructor - forces use of factory constructors
  SequencedMessage._({
    required this.type,
    this.sequence,
    this.payload,
    this.ackSequence,
    this.nackFromSequence,
    this.batchPayload,
    this.chunkId,
    this.chunkIndex,
    this.chunkTotal,
  });

  // --- FACTORY CONSTRUCTORS FOR CREATING MESSAGES ---

  /// Creates a 'data' message with a payload.
  // Updated Data Factory
  factory SequencedMessage.data({
    required int sequence,
    required Uint8List payload,
    String? chunkId,
    int? chunkIndex,
    int? chunkTotal,
  }) {
    return SequencedMessage._(
      type: SequencedMessageType.data,
      sequence: sequence,
      payload: payload,
      chunkId: chunkId,
      chunkIndex: chunkIndex,
      chunkTotal: chunkTotal,
    );
  }

  /// Creates an 'ack' message for a given sequence number.
  factory SequencedMessage.ack({required int sequence}) {
    return SequencedMessage._(
      type: SequencedMessageType.ack,
      ackSequence: sequence,
    );
  }

  /// Creates a 'nack' message requesting a resend.
  factory SequencedMessage.nack({required int fromSequence}) {
    return SequencedMessage._(
      type: SequencedMessageType.nack,
      nackFromSequence: fromSequence,
    );
  }

  /// Creates a 'batch' message containing multiple data payloads.
  factory SequencedMessage.batch({required List<DataPayload> payloads}) {
    return SequencedMessage._(
      type: SequencedMessageType.batch,
      batchPayload: payloads,
    );
  }

  // --- JSON SERIALIZATION / DESERIALIZATION ---

  /// Deserializes a JSON map into the correct SequencedMessage type.
  factory SequencedMessage.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String;
    final type = SequencedMessageType.values.firstWhere(
      (e) => e.name == typeName,
      orElse: () => throw ArgumentError('Invalid message type: $typeName'),
    );

    switch (type) {
      case SequencedMessageType.data:
        return SequencedMessage.data(
          sequence: json['sequence'],
          payload: base64Decode(json['payload']),
          chunkId: json['chunkId'],
          chunkIndex: json['chunkIndex'],
          chunkTotal: json['chunkTotal'],
        );
      case SequencedMessageType.ack:
        return SequencedMessage.ack(
          sequence: json['ackSequence'],
        );
      case SequencedMessageType.nack:
        return SequencedMessage.nack(
          fromSequence: json['nackFromSequence'],
        );
      case SequencedMessageType.batch:
        final payloads = (json['batchPayload'] as List)
            .map((item) => DataPayload.fromJson(item as Map<String, dynamic>))
            .toList();
        return SequencedMessage.batch(
          payloads: payloads,
        );
    }
  }

  /// Serializes the message object into a JSON map.
  Map<String, dynamic> toJson() {
    // --- THE FIX IS HERE ---
    // Use .name to serialize the enum as a string ("data", "ack", etc.)
    final Map<String, dynamic> json = {'type': type.name};

    switch (type) {
      case SequencedMessageType.data:
        json['sequence'] = sequence;
        json['payload'] = base64Encode(payload!);
        // Add chunking info if it exists
        if (chunkId != null) json['chunkId'] = chunkId;
        if (chunkIndex != null) json['chunkIndex'] = chunkIndex;
        if (chunkTotal != null) json['chunkTotal'] = chunkTotal;
        break;
      case SequencedMessageType.ack:
        json['ackSequence'] = ackSequence;
        break;
      case SequencedMessageType.nack:
        json['nackFromSequence'] = nackFromSequence;
        break;
      case SequencedMessageType.batch:
        json['batchPayload'] = batchPayload!.map((p) => p.toJson()).toList();
        break;
    }
    return json;
  }
}
