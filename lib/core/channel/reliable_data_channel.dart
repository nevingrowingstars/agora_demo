import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:agora_demo/core/channel/sequence_message.dart';
import 'package:agora_demo/core/util/app_logger_util.dart';
import 'package:uuid/uuid.dart';


enum DeliveryGuarantee {
  /// The message will be sequenced, chunked, and re-transmitted if lost.
  reliable,
  /// The message will be sent once, "fire-and-forget". Used for ping/pong.
  unreliable,
}

class ReliableDataChannel {
  // Callbacks provided by the owner (WebRTC or Agora strategy)
  final Future<void> Function(Uint8List rawData) _sendRawDataCallback;
  final void Function(Uint8List payload) _onDataReceivedCallback;

  // --- SENDER STATE ---
  int _nextSequenceNumber = 1;
  // We now store the full JSON payload we sent, not just the raw data.
  final Map<int, Uint8List> _sentHistory = {};

  // --- RECEIVER STATE ---
  int _lastProcessedSequence = 0;
  int _lastAckReceived = 0;

  // We subtract some overhead for the JSON keys, sequence numbers, etc.
  static const int _defaultChunkSize = 16 * 1024; 
  final int maxChunkPayloadSize;
  final Duration delayBetweenChunks; // New parameter

  // Key: chunkId, Value: Map of chunkIndex -> chunkData
  final Map<String, Map<int, Uint8List>> _chunkBuffer = {};

  ReliableDataChannel({
    required Future<void> Function(Uint8List rawData) sendRawDataCallback,
    required void Function(Uint8List payload) onDataReceivedCallback,
    int? maxChunkSize,
    this.delayBetweenChunks = const Duration(milliseconds: 0), 
  })  : _sendRawDataCallback = sendRawDataCallback,
        _onDataReceivedCallback = onDataReceivedCallback,
        maxChunkPayloadSize = maxChunkSize ?? _defaultChunkSize;

  /// Public method to send application data reliably.
  void sendData(Uint8List data, { bool isReliable = true,
   bool bypassChunking = false}) {
    GSLogger.log("Data size: ${data.length}");
  

    if (!isReliable) {
      // --- UNRELIABLE MESSAGES (ping, pong) ---
      // These are always small and fire-and-forget.
      final message = {
        'type': 'unreliable_data',
        'payload': jsonDecode(utf8.decode(data)),
      };
      _sendRawJson(message);
      return;
    }

    // 2. Pass the compressed data to the chunking/sending logic.
    if (bypassChunking) {
      // If bypassing, send it directly, regardless of size.
      // WebRTC's SCTP layer will handle the fragmentation.
      _sendSingleData(data);
    } else{
      if (maxChunkPayloadSize <= 0 || data.length <= maxChunkPayloadSize) {
        _sendSingleData(data);
      } else {
        _sendChunkedData(data);
      }
    }
  }

  

  /// Sends a single, non-chunked message.
  void _sendSingleData(Uint8List data) {
    // 1. Generate the next sequence number.
    final int sequence = _nextSequenceNumber++;

    // 2. Create the typed message object.
    final messageToSend =
        SequencedMessage.data(sequence: sequence, payload: data);

    // 3. Store the ORIGINAL raw data in our history map for potential resends.
    //    This is crucial for handling NACKs later.
    _sentHistory[sequence] = data;

    GSLogger.log("ReliableChannel: Sending data with sequence #$sequence");

    // 4. Send the message to the peer. This is the one and only send call.
    _sendSequencedMessage(messageToSend);
  }

  /// Splits a large payload into chunks and sends them.
  void _sendChunkedData(Uint8List data) async {
    final chunkId = Uuid().v4();
    final totalChunks = (data.length / maxChunkPayloadSize).ceil();
    final firstSequence = _nextSequenceNumber;
    _sentHistory[firstSequence] = data; 

    for (var i = 0; i < totalChunks; i++) {
      final start = i * maxChunkPayloadSize;
      final end = (start + maxChunkPayloadSize > data.length)
          ? data.length
          : start + maxChunkPayloadSize;
      final chunkData = data.sublist(start, end);

      // Each chunk gets its own unique sequence number for NACKs.
      final sequence = _nextSequenceNumber++;

      final message = SequencedMessage.data(
        sequence: sequence,
        payload: chunkData,
        chunkId: chunkId,
        chunkIndex: i,
        chunkTotal: totalChunks,
      );
      _sendSequencedMessage(message);
      if (delayBetweenChunks.inMilliseconds > 0) {
        await Future.delayed(delayBetweenChunks);
      }
    }
  }

  void _sendRawJson(Map<String, dynamic> jsonData) {
    try {
      // 1. Convert the Dart Map into a JSON formatted string.
      final jsonString = jsonEncode(jsonData);
      
      // 2. Encode the string into a list of bytes (Uint8List).
      final messageBytes = utf8.encode(jsonString);
      
      // 3. Call the callback provided by the strategy to send the raw bytes.
      _sendRawDataCallback(messageBytes);
      
      GSLogger.log("ReliableChannel: Sent raw JSON message: ${jsonString}");
    } catch (e) {
      GSLogger.log("Error in _sendRawJson: $e");
    }
  }

  

  /// Public method to be called when raw data arrives.
  /// Public method to be called when raw data arrives from the transport layer.
  void handleRawData(Uint8List rawData) {
    try {
      final json = jsonDecode(utf8.decode(rawData));
      final message = SequencedMessage.fromJson(json);

      switch (message.type) {
        case SequencedMessageType.data:
          _handleDataMessage(message);
          break;
        case SequencedMessageType.nack:
          _handleNackMessage(message.nackFromSequence!);
          break;
        case SequencedMessageType.batch:
          _handleBatchMessage(message.batchPayload!);
          break;
        case SequencedMessageType.ack:
          // In a NACK system, ACKs are optional, can be used for logging or latency.
          _handleAckMessage(message.ackSequence!); 
          break;
      }
    } catch (e) {
      GSLogger.log("ReliableChannel: Error processing raw data: $e");
    }
  }

  // --- NEW RECEIVER LOGIC ---

  void _handleDataMessage(SequencedMessage message) {
    final sequence = message.sequence!;
    final payload = message.payload!;

    GSLogger.log("ReliableChannel: _handleDataMessage ");
    GSLogger.log("Received sequence #${sequence}.");
    GSLogger.log("LastProcessed sequence #${_lastProcessedSequence}.");
    // If it's a chunk, handle it separately.
    if (message.chunkId != null) {
      _handleChunkedMessage(message);
      return;
    }

    if (sequence == _lastProcessedSequence + 1) {
      _processPayload(sequence, payload);
    } else if (sequence > _lastProcessedSequence) {
      // Out of order. Discard and wait for resend.
      GSLogger.log(
          "ReliableChannel: Discarding out-of-order sequence #${sequence}. Expecting #${_lastProcessedSequence + 1}");
    }
    _sendAck(_lastProcessedSequence);
  }

  void _handleChunkedMessage(SequencedMessage message) {
    final chunkId = message.chunkId!;
    final index = message.chunkIndex!;
    final total = message.chunkTotal!;

    _chunkBuffer.putIfAbsent(chunkId, () => {});
    _chunkBuffer[chunkId]![index] = message.payload!;

    if (_chunkBuffer[chunkId]!.length == total) {
      final chunks = _chunkBuffer.remove(chunkId)!;
      List<int> fullDataBytes = [];
      for (int i = 0; i < total; i++) {
        fullDataBytes.addAll(chunks[i]!);
      }

      final fullPayload = Uint8List.fromList(fullDataBytes);
      // Now that it's reassembled, process it like a single message.
      _processPayload(message.sequence!, fullPayload);
    }
  }

  void _processPayload(int sequence, Uint8List payload) {
    GSLogger.log("Processing payload for sequence #$sequence.");

    /*
    // 1. Decompress the received payload.
    final decompressedData = gzip.decode(payload);
    // 2. Convert the List<int> into a Uint8List before passing it on.
    final Uint8List originalData = Uint8List.fromList(decompressedData);*/
    _onDataReceivedCallback(payload);
    _lastProcessedSequence = sequence;
  }

  
  void _handleAckMessage(int ackSequence) {
    GSLogger.log(
        "Received ACK for #${ackSequence}. My next expected ACK is #${_lastAckReceived + 1}");

    if (ackSequence > _lastAckReceived) {
      // This is a new, valid ACK. Clean up the history.
      _lastAckReceived = ackSequence;
      _sentHistory.removeWhere((seq, _) => seq <= ackSequence);
      GSLogger.log("History cleared up to #${ackSequence}.");
    } else {
      // --- RESEND PATH: This is a stale or duplicate ACK ---
      // This implies the receiver is stuck and has missed a message.

      final int nextExpectedByReceiver = ackSequence + 1;
      GSLogger.log(
          "ReliableChannel: Received STALE ACK for #${ackSequence}. Receiver is missing #${nextExpectedByReceiver}.");

      // Check if we have the missing message in our history and resend it.
      if (_sentHistory.containsKey(nextExpectedByReceiver)) {
        GSLogger.log(
            "ReliableChannel: Resending message #${nextExpectedByReceiver}.");

        // Re-create the SequencedMessage and send it.
        final messageToResend = SequencedMessage.data(
          sequence: nextExpectedByReceiver,
          payload: _sentHistory[nextExpectedByReceiver]!,
        );
        _sendSequencedMessage(messageToResend);
      }
    }
  }



  void _sendAck(int sequence) {
    final ackMessage = SequencedMessage.ack(sequence: sequence);
    _sendSequencedMessage(ackMessage);
  }


  // This method now takes just the sequence number, not the whole map.
  // This is cleaner as it's the only piece of data from the NACK message.
  void _handleNackMessage(int fromSequence) {
    final payloadsToResend = <DataPayload>[];
    for (int i = fromSequence; i < _nextSequenceNumber; i++) {
      if (_sentHistory.containsKey(i)) {
        payloadsToResend.add(DataPayload(sequence: i, data: _sentHistory[i]!));
      }
    }
    if (payloadsToResend.isNotEmpty) {
      _sendSequencedMessage(SequencedMessage.batch(payloads: payloadsToResend));
    }
  }

  void _handleBatchMessage(List<DataPayload> batchPayload) {
    batchPayload.sort((a, b) => a.sequence.compareTo(b.sequence));
    for (final payload in batchPayload) {
      _handleDataMessage(SequencedMessage.data(
          sequence: payload.sequence, payload: payload.data));
    }
  }

  void _sendNackRequest(int fromSequence) {
    _sendSequencedMessage(SequencedMessage.nack(fromSequence: fromSequence));
  }

  void _sendSequencedMessage(SequencedMessage message) {
    final jsonString = jsonEncode(message.toJson());
    GSLogger.log("_sendSequencedMessage: ${jsonString} ");
    final messageBytes = utf8.encode(jsonString);
    _sendRawDataCallback(messageBytes);
  }

  void reset() {
    GSLogger.log("ReliableDataChannel: Resetting sequence numbers and buffers.");
    _nextSequenceNumber = 1;
    _lastProcessedSequence = 0;
    _sentHistory.clear();
    _chunkBuffer.clear();
  }

  void dispose() {
    reset();
  }
}
