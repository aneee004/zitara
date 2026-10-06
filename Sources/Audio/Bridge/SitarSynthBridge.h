#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Thin Objective-C++ wrapper around the C++ SitarSynth.
/// Swift talks to this; this talks to C++.
/// All setters are safe to call from the main/UI thread at any time
/// (they only write atomics). `renderInto:frames:` is called by the
/// audio render thread only.
@interface SitarSynthBridge : NSObject

- (void)prepareWithSampleRate:(double)sampleRate;

/// RT render callback target. Mono float output.
- (void)renderInto:(float *)buffer frames:(int)frames;

/// Note events (monophonic, last-note priority handled by caller).
- (void)noteOnWithFrequency:(float)freq velocity:(float)velocity;
- (void)slideToFrequency:(float)freq;
/// Hammer-on / pull-off: fast pitch step with a light re-excitation (accent
/// 0...1), no full pluck. Gate stays open.
- (void)legatoToFrequency:(float)freq accent:(float)accent;
- (void)noteOff;

/// Live per-note dynamics, 0...1 (1 = neutral). Driven by Pencil pressure.
- (void)setExpression:(float)value;

/// Live modulation (XY pad). Both in 0...1.
- (void)setBrightness:(float)value;
- (void)setBuzz:(float)value;

/// Fader-driven params, all 0...1.
- (void)setSustain:(float)value;
- (void)setGlide:(float)value;
- (void)setSympMix:(float)value;
- (void)setRoom:(float)value;

/// Sustain button. Holds gate open while pressed.
- (void)setSustainHold:(BOOL)held;

/// Vibrato (driven by drag on the sustain button).
- (void)setVibratoRate:(float)hz;
- (void)setVibratoDepth:(float)cents;

/// Smoothed |output| level, published by the audio thread. UI reads this
/// on a display link to drive touch bloom / meters. Never blocks.
- (float)envelopeLevel;

/// Retune one sympathetic string (index 0..6).
- (void)setSympatheticFrequency:(float)freq atIndex:(int)index;

@end

NS_ASSUME_NONNULL_END
