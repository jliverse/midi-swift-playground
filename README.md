# Swift Playground for MIDI Devices
For app developers and musicians who use MIDI keyboards, this Swift playground starts available MIDI devices using built-in instruments.

## Frequently Asked Questions

### 💁 What is MIDI?
[MIDI](https://www.midi.org/) is a protocol for describing music and connecting musical instruments, like my .

### 🎹 How does this Swift playground work?
This project was an exercise in learning the available APIs on macOS, so you'll see my own code around the available frameworks—I wanted to provide a minimal example.
```swift
// Set up the default MIDI output on macOS with Harpsichord on Channel 1.
let fn = MIDI().receiver()
Channel(fn, channel: 1).assign(program: 7, msb: 121, lsb: 0)
```
The `fn` we created above is a function that accepts [three-byte MIDI messages](https://www.midi.org/midi-articles/about-midi-part-3-midi-messages). We can identify MIDI hardware and just pass along its messages.
```swift
MIDISources<MIDIObjectRef>().forEach { ref in _ = MIDIEndpoint(ref).connect(fn) }
```
## References
* [CoreMIDI](https://developer.apple.com/documentation/coremidi/) 
* [General MIDI Level 2 Sounds](https://en.wikipedia.org/wiki/General_MIDI_Level_2)

## License
This project is licensed under the _MIT License_.
