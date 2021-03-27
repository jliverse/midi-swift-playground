/*:
 🎹 For app developers and musicians who use MIDI keyboards, this Swift playground starts available MIDI devices using built-in instruments. Unlike larger apps like GarageBand, this project is a fast way to play USB piano keyboards through your speakers or headphones and serves as a minimal platform for creating more useful apps.
 👷 [Joe Liversedge](http://twitter.com/jliverse)
*/
/*
 MIT License

 Copyright (c) 2021 Joseph Liversedge

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
*/
import AVFoundation
import CoreMIDI
import PlaygroundSupport
PlaygroundSupport.PlaygroundPage.current.needsIndefiniteExecution = true

/// A function that accepts a MIDI message.
///
/// - Parameters:
///   - status: the eight-bit status
///   - a: the first data byte
///   - b: the second data byte (optional)
///
/// MIDI messages are sent and received by MIDI devices and include a status byte with subsequent data bytes.
typealias MIDIMessageReceiver = (_ status: UInt8, _ a: UInt8, _ b: UInt8) -> Void

/// An `AUGraph` instance that can start default MIDI output.
public class MIDI {
  var graph: AUGraph?
  var playing: Bool = false
  convenience init() {
    self.init(graph: nil)
  }
  init(graph: AUGraph?) {
    if graph != nil {
      self.graph = graph
    } else {
      _ = NewAUGraph(&self.graph)
    }
  }
  func stop() {
    guard let graph = graph else { return }
    playing = false
    _ = AUGraphStop(graph)
  }
  /// Returns a closure that accepts a MIDI byte triple.
  ///
  /// - Returns: A function that receives three MIDI bytes and sends them to the AudioUnit DLS MIDI output.
  func receiver() -> MIDIMessageReceiver {
    guard let graph = graph else { return { (_, _, _) in } }
    _ = AUGraphOpen(graph)
    let source = createWith(kAudioUnitType_MusicDevice, kAudioUnitSubType_DLSSynth)
    let sourceID = AudioUnitElement(0)
    let dest = createWith(kAudioUnitType_Output, kAudioUnitSubType_DefaultOutput)
    let destID = AudioUnitElement(0)
    _ = AUGraphConnectNodeInput(graph, source.node, sourceID, dest.node, destID)
    _ = AUGraphInitialize(graph)
    _ = AUGraphStart(graph)
    playing = true
    return { (status: UInt8, a: UInt8, b: UInt8) in
      guard self.playing else { return }
      MusicDeviceMIDIEvent(source.audioUnit!, UInt32(status), UInt32(a), UInt32(b), 0)
    }
  }
  private func createWith(_ type: UInt32, _ subType: UInt32) -> (node: AUNode, audioUnit: AudioUnit?) {
    var acd = AudioComponentDescription(
      componentType: OSType(type),
      componentSubType: OSType(subType),
      componentManufacturer: OSType(kAudioUnitManufacturer_Apple),
      componentFlags: 0,
      componentFlagsMask: 0)
    var node = AUNode()
    var au: AudioUnit?
    _ = AUGraphAddNode(graph!, &acd, &node)
    _ = AUGraphNodeInfo(graph!, node, nil, &au)
    return (node, au)
  }
}
/// A MIDI source endpoint that connects its MIDI data packets to a receiver function.
class MIDIEndpoint {
  let ref: MIDIEndpointRef
  init(_ ref: MIDIEndpointRef) {
    self.ref = ref
  }
  func connect(_ receiverFn: @escaping MIDIMessageReceiver) -> () -> Void {
    let fn: MIDIReadBlock  = { (packets, refCon) in
      for i in MIDIPackets(packets.pointee) {
        receiverFn(UInt8(i.data.0), UInt8(i.data.1), UInt8(i.data.2))
        print(String(format: "0x%02x 0x%02x 0x%02x", i.data.0, i.data.1, i.data.2))
      }
    }
    var clientRef: MIDIClientRef = 0
    var portRef: MIDIPortRef = 0
    _ = MIDIClientCreateWithBlock("4c47dc89-da55-4adf-8cca-367b58d4e32e" as CFString, &clientRef, nil) // { [weak self] (notification) in }
    _ = MIDIInputPortCreateWithBlock(clientRef, "37a48f2e-efd0-4aad-85ff-03709239df9d" as CFString, &portRef, fn)
    _ = MIDIPortConnectSource(portRef, ref, nil)
    return {
      MIDIPortDispose(portRef)
      MIDIClientDispose(clientRef)
    }
  }
  /// An interable `MIDIPacketList`.
  private struct MIDIPackets: Sequence, IteratorProtocol {
    var count: UInt32
    var index: UInt32 = 0
    var packet: UnsafeMutablePointer<MIDIPacket>?
    init(_ list: MIDIPacketList) {
      let ptr = UnsafeMutablePointer<MIDIPacket>.allocate(capacity: 1)
      ptr.initialize(to: list.packet)
      self.packet = ptr
      self.count = list.numPackets
    }
    public mutating func next() -> MIDIPacket? {
      guard self.index < self.count else { return nil }
      let lastPacket = self.packet!
      self.packet = MIDIPacketNext(self.packet!)
      self.index += 1
      return lastPacket.pointee
    }
  }
}
/// An iterable list of `MIDIEndpoint ` sources.
public struct MIDISources<MIDIObjectRef>: Sequence, IteratorProtocol {
  var count: Int
  var index: Int = 0
  init() {
    count = MIDIGetNumberOfSources()
  }
  public mutating func next() -> MIDIEndpointRef? {
    guard index < count else { return nil }
    let ref = MIDIGetSource(index)
    index += 1
    return ref
  }
}
/// A MIDI object that can return its own properties.
public class MIDIEntityProperties {
  let entityRef: MIDIEntityRef
  var name: String { return from(kMIDIPropertyName) }
  var offline: Int32 { return from(kMIDIPropertyOffline) }
  convenience init(ref: MIDIEndpointRef) {
    var entityRef: MIDIEntityRef = 0
    _ = MIDIEndpointGetEntity(ref, &entityRef)
    self.init(entityRef)
  }
  init(_ entityRef: MIDIEntityRef) {
    self.entityRef = entityRef
  }
  private func from(_ propertyID: CFString) -> String {
    var str: Unmanaged<CFString>?
    _ = MIDIObjectGetStringProperty(entityRef, propertyID, &str)
    return str!.takeRetainedValue() as String
  }
  private func from(_ propertyID: CFString) -> Int32 {
    var out: Int32 = 0
    _ = MIDIObjectGetIntegerProperty(entityRef, propertyID, &out)
    return out
  }
}
/// Channel assignment for a MIDI receiver.
class Channel {
  let fn: MIDIMessageReceiver
  let channel: UInt8
  init(_ receiver: @escaping MIDIMessageReceiver, channel: UInt8) {
    self.fn = receiver
    self.channel = channel
  }
  func assign(program: UInt8, msb: UInt8, lsb: UInt8) {
    fn(0xc0 | channel, program, 0x00)
    fn(0xb0 | channel, 0x00, msb)
    fn(0xb0 | channel, 0x20, lsb)
  }
}

// Set up the default MIDI output on macOS with Harpsichord on Channel 1.
let fn = MIDI().receiver()
Channel(fn, channel: 1).assign(program: 7, msb: 121, lsb: 0)

// Find all MIDI sources and send its data to the default output.
for ref in MIDISources<MIDIObjectRef>() {
  print("Connecting \(MIDIEntityProperties(ref).name)")
  _ = MIDIEndpoint(ref).connect(fn)
}
