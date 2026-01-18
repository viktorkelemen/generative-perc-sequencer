(
// =============================================
// Generative Percussion Sequencer
// Recreation of Max/MSP patch - with GUI
// =============================================

// Stop existing sequencer if re-running
~seq !? { ~seq.stop };
~guiUpdater !? { ~guiUpdater.stop };
~counterUpdater !? { ~counterUpdater.stop };

// SynthDef for percussion - Mark Fell style FM
SynthDef(\perc, {
    arg freq = 440, amp = 0.5, pan = 0, dur = 0.1,
        ratio = 1.5, index = 4, indexDecay = 0.8,
        feedback = 0.1, click = 1;
    var sig, mod, env, indexEnv, clickEnv, localIn;

    // Sharp amplitude envelope
    env = EnvGen.kr(
        Env([0, 1, 0.3, 0], [0.001, dur * 0.3, dur * 0.7], [-8, -4, -6]),
        doneAction: 2
    );

    // Index envelope - fast decay for that FM "pluck"
    indexEnv = EnvGen.kr(
        Env([index, index * 0.1, 0], [indexDecay * dur, dur], [-6, -4])
    );

    // Click transient
    clickEnv = EnvGen.kr(Env.perc(0.0001, 0.003)) * click;

    // Feedback FM for metallic harmonics
    localIn = LocalIn.ar(1) * feedback;

    // Modulator with feedback
    mod = SinOsc.ar(freq * ratio + (localIn * freq * 2), 0, freq * indexEnv);

    // Carrier
    sig = SinOsc.ar(freq + mod);

    // Feed back the signal
    LocalOut.ar(sig);

    // Add click transient (band-limited impulse)
    sig = sig + (BPF.ar(Impulse.ar(0), freq * 4, 0.5) * clickEnv * 8);

    // Gentle saturation for edge
    sig = (sig * 1.5).tanh;

    sig = sig * env * amp;
    Out.ar(0, Pan2.ar(sig, pan));
}).add;

// Additional FM variant - more metallic/inharmonic
SynthDef(\perc2, {
    arg freq = 440, amp = 0.5, pan = 0, dur = 0.1,
        ratio = 1.414, index = 3, feedback = 0;  // Unified params
    var sig, mod1, mod2, env, indexEnv1, indexEnv2;
    var ratio2 = ratio * 2.236;  // Second ratio derived from first (√5 multiplier)

    env = EnvGen.kr(
        Env([0, 1, 0.2, 0], [0.0005, dur * 0.2, dur * 0.8], [-10, -4, -8]),
        doneAction: 2
    );

    indexEnv1 = EnvGen.kr(Env([index, index * 0.05], [dur * 0.5], [-8]));
    indexEnv2 = EnvGen.kr(Env([index * 0.7, index * 0.02], [dur * 0.3], [-10]));

    // Two modulators - inharmonic ratios for bell/metallic tones
    mod1 = SinOsc.ar(freq * ratio, 0, freq * indexEnv1);
    mod2 = SinOsc.ar(freq * ratio2 + mod1 + (feedback * mod1), 0, freq * indexEnv2);

    sig = SinOsc.ar(freq + mod2);
    sig = (sig * 1.3).tanh;
    sig = sig * env * amp;

    Out.ar(0, Pan2.ar(sig, pan));
}).add;

// Glitchy digital blip
SynthDef(\perc3, {
    arg freq = 440, amp = 0.5, pan = 0, dur = 0.1,
        ratio = 2.01, index = 12, feedback = 0, bits = 8;  // Unified params + bits
    var sig, mod, env, indexEnv, localIn;

    env = EnvGen.kr(
        Env([0, 1, 0], [0.0001, dur], [-4, -8]),
        doneAction: 2
    );

    indexEnv = EnvGen.kr(Env([index, 0.5], [dur * 0.4], [-10]));

    // Feedback for extra grit
    localIn = LocalIn.ar(1) * feedback;
    mod = SinOsc.ar(freq * ratio + (localIn * freq), 0, freq * indexEnv);
    sig = SinOsc.ar(freq + mod);
    LocalOut.ar(sig);

    // Bit crushing for digital grit
    sig = (sig * (2 ** (bits - 1))).round / (2 ** (bits - 1));

    sig = sig * env * amp;
    Out.ar(0, Pan2.ar(sig, pan));
}).add;

// State
~seqEnabled = true;
~counter = 0;
~stepIndex = 0;
~notes = [36, 85, 42];
~interval = 0.1;

// New parameters
~noteDur = 0.1;           // Note duration
~velMin = 20;             // Minimum velocity
~velMax = 100;            // Maximum velocity
~density = 1.0;           // Probability of note playing (0-1)
~panSpread = 0.0;         // Random pan amount (0-1)
~playMode = \random;      // \random, \forward, \backward, \pingpong
~pingpongDir = 1;         // Direction for pingpong mode
~crescendoLen = 100;      // Steps before velocity cycle resets
~swing = 0.0;             // Swing amount (0-1)
~swingPhase = 0;          // Tracks swing

// FM parameters - Mark Fell style
~synthType = \perc;       // \perc, \perc2, \perc3
~fmRatio = 1.5;           // Modulator ratio (1.414 = metallic, integers = harmonic)
~fmIndex = 4;             // Modulation depth
~fmFeedback = 0.1;        // Feedback amount
~ratioRandom = 0.0;       // Random ratio variation per note
~bits = 8;                // Bit depth for perc3 (1-16)

// Control functions
~enableSeq  = { ~seqEnabled = true;  "ON".postln };
~disableSeq = { ~seqEnabled = false; "OFF".postln };
~stopSeq    = { ~seq !? { ~seq.stop }; "STOPPED".postln };

// Note selection based on play mode
~getNextNote = {
    var note;
    switch(~playMode,
        \random, {
            note = ~notes.choose;
        },
        \forward, {
            note = ~notes[~stepIndex % ~notes.size];
            ~stepIndex = ~stepIndex + 1;
        },
        \backward, {
            note = ~notes[(~notes.size - 1) - (~stepIndex % ~notes.size)];
            ~stepIndex = ~stepIndex + 1;
        },
        \pingpong, {
            note = ~notes[~stepIndex];
            ~stepIndex = ~stepIndex + ~pingpongDir;
            if(~stepIndex >= (~notes.size - 1)) { ~pingpongDir = -1 };
            if(~stepIndex <= 0) { ~pingpongDir = 1 };
            ~stepIndex = ~stepIndex.clip(0, ~notes.size - 1);
        }
    );
    note;
};

// Start sequencer
fork {
    s.sync;

    ~seq = Routine({
        loop {
            var waitTime;

            if (~seqEnabled) {
                // Density check - probability of playing
                if (~density.coin) {
                    var note, baseVel, randFactor, amp, pan;

                    note = ~getNextNote.value;

                    // Velocity with crescendo cycle
                    ~counter = (~counter + 1) % ~crescendoLen;
                    baseVel = (~counter + 1).linlin(1, ~crescendoLen, ~velMin, ~velMax);
                    randFactor = rrand(0.8, 1.0);
                    amp = (baseVel * randFactor / 127).clip(0.05, 0.9);

                    // Random pan
                    pan = rrand(~panSpread.neg, ~panSpread);

                    // Use selected synth with FM parameters
                    Synth(~synthType, [
                        \freq, note.midicps,
                        \amp, amp,
                        \dur, ~noteDur,
                        \pan, pan,
                        \ratio, ~fmRatio + rrand(~ratioRandom.neg, ~ratioRandom),
                        \index, ~fmIndex,
                        \feedback, ~fmFeedback,
                        \bits, ~bits
                    ]);
                };
            };

            // Swing timing
            ~swingPhase = 1 - ~swingPhase;
            waitTime = if(~swingPhase == 1) {
                ~interval * (1 + (~swing * 0.5))
            } {
                ~interval * (1 - (~swing * 0.5))
            };
            waitTime.wait;
        };
    }).play;

    "=== Sequencer Running ===".postln;
};

// =============================================
// GUI
// =============================================
{
    var win, enableBtn, tempoSlider, tempoNum;
    var durSlider, durNum, densitySlider, densityNum;
    var velMinSlider, velMaxSlider, velMinNum, velMaxNum;
    var panSlider, panNum, swingSlider, swingNum;
    var crescendoSlider, crescendoNum;
    var fmRatioNum, fmIndexNum, fmFeedbackNum, fmRatioRndNum, bitsNum;
    var modeButtons, presetButtons;
    var customNoteField;
    var presets;

    presets = (
        drums: [36, 38, 42, 46],
        perc:  [36, 85, 42],
        melodic: [60, 62, 64, 67],
        bass: [24, 31, 36, 38],
        high: [72, 74, 76, 79],
        chromatic: [60, 61, 62, 63, 64, 65],
        pentatonic: [60, 62, 64, 67, 69]
    );

    Window.allWindows.do { |w| if(w.name == "Perc Sequencer") { w.close } };

    win = Window("Perc Sequencer", Rect(100, 100, 340, 860))
        .front
        .alwaysOnTop_(true);

    win.view.decorator = FlowLayout(win.view.bounds, Point(10,10), Point(5,5));

    // === TITLE ===
    StaticText(win, 320@25)
        .string_("GENERATIVE PERCUSSION SEQUENCER")
        .font_(Font("Helvetica", 14, true))
        .align_(\center);

    win.view.decorator.nextLine;

    // === TRANSPORT ===
    StaticText(win, 320@15).string_("─── Transport ───").align_(\center);

    enableBtn = Button(win, 155@40)
        .states_([
            ["▶ ENABLE", Color.white, Color.green(0.5)],
            ["■ DISABLE", Color.white, Color.red(0.5)]
        ])
        .value_(1)
        .action_({ |btn|
            if(btn.value == 1) { ~enableSeq.value } { ~disableSeq.value };
        });

    Button(win, 155@40)
        .states_([["⏹ STOP", Color.white, Color.gray(0.3)]])
        .action_({
            ~stopSeq.value;
            enableBtn.value_(0);
        });

    win.view.decorator.nextLine;

    // === TIMING ===
    StaticText(win, 320@15).string_("─── Timing ───").align_(\center);

    StaticText(win, 60@20).string_("Tempo");
    tempoSlider = Slider(win, 200@20)
        .value_(~interval.linlin(0.02, 0.5, 0, 1))
        .action_({ |sl|
            var ms = sl.value.linlin(0, 1, 20, 500);
            ~interval = ms / 1000;
            tempoNum.string_(ms.round(1).asString ++ " ms");
        });
    tempoNum = StaticText(win, 50@20).string_("100 ms");

    StaticText(win, 60@20).string_("Duration");
    durSlider = Slider(win, 200@20)
        .value_(~noteDur.linlin(0.01, 0.5, 0, 1))
        .action_({ |sl|
            ~noteDur = sl.value.linlin(0, 1, 0.01, 0.5);
            durNum.string_(~noteDur.round(0.01).asString ++ " s");
        });
    durNum = StaticText(win, 50@20).string_("0.1 s");

    StaticText(win, 60@20).string_("Swing");
    swingSlider = Slider(win, 200@20)
        .value_(0)
        .action_({ |sl|
            ~swing = sl.value;
            swingNum.string_((~swing * 100).round(1).asString ++ "%");
        });
    swingNum = StaticText(win, 50@20).string_("0%");

    win.view.decorator.nextLine;

    // === VELOCITY ===
    StaticText(win, 320@15).string_("─── Velocity ───").align_(\center);

    StaticText(win, 60@20).string_("Vel Min");
    velMinSlider = Slider(win, 200@20)
        .value_(~velMin / 127)
        .action_({ |sl|
            ~velMin = (sl.value * 127).round(1);
            velMinNum.string_(~velMin.asString);
        });
    velMinNum = StaticText(win, 50@20).string_("20");

    StaticText(win, 60@20).string_("Vel Max");
    velMaxSlider = Slider(win, 200@20)
        .value_(~velMax / 127)
        .action_({ |sl|
            ~velMax = (sl.value * 127).round(1);
            velMaxNum.string_(~velMax.asString);
        });
    velMaxNum = StaticText(win, 50@20).string_("100");

    StaticText(win, 60@20).string_("Cycle Len");
    crescendoSlider = Slider(win, 200@20)
        .value_(~crescendoLen.linlin(10, 500, 0, 1))
        .action_({ |sl|
            ~crescendoLen = sl.value.linlin(0, 1, 10, 500).round(1);
            crescendoNum.string_(~crescendoLen.asString);
        });
    crescendoNum = StaticText(win, 50@20).string_("100");

    win.view.decorator.nextLine;

    // === VARIATION ===
    StaticText(win, 320@15).string_("─── Variation ───").align_(\center);

    StaticText(win, 60@20).string_("Density");
    densitySlider = Slider(win, 200@20)
        .value_(1)
        .action_({ |sl|
            ~density = sl.value;
            densityNum.string_((~density * 100).round(1).asString ++ "%");
        });
    densityNum = StaticText(win, 50@20).string_("100%");

    StaticText(win, 60@20).string_("Pan Spread");
    panSlider = Slider(win, 200@20)
        .value_(0)
        .action_({ |sl|
            ~panSpread = sl.value;
            panNum.string_((~panSpread * 100).round(1).asString ++ "%");
        });
    panNum = StaticText(win, 50@20).string_("0%");

    win.view.decorator.nextLine;

    // === FM SYNTHESIS ===
    StaticText(win, 320@15).string_("─── FM Synthesis ───").align_(\center);

    // Synth type buttons
    [\perc, \perc2, \perc3].do { |synth|
        Button(win, 100@25)
            .states_([
                [synth.asString, Color.black, Color.gray(0.75)],
                [synth.asString, Color.white, Color.cyan(0.6)]
            ])
            .value_(if(~synthType == synth) { 1 } { 0 })
            .action_({ |btn|
                ~synthType = synth;
                ("Synth: " ++ synth).postln;
                win.view.children.do { |child|
                    if(child.class == Button) {
                        if([\perc, \perc2, \perc3].includes(child.states[0][0].asSymbol)) {
                            child.value_(if(child.states[0][0].asSymbol == synth) { 1 } { 0 });
                        };
                    };
                };
            });
    };

    win.view.decorator.nextLine;

    StaticText(win, 60@20).string_("FM Ratio");
    Slider(win, 200@20)
        .value_(~fmRatio.linlin(0.5, 8, 0, 1))
        .action_({ |sl|
            ~fmRatio = sl.value.linlin(0, 1, 0.5, 8);
            fmRatioNum.string_(~fmRatio.round(0.01).asString);
        });
    fmRatioNum = StaticText(win, 50@20).string_(~fmRatio.round(0.01).asString);

    StaticText(win, 60@20).string_("FM Index");
    Slider(win, 200@20)
        .value_(~fmIndex.linlin(0, 20, 0, 1))
        .action_({ |sl|
            ~fmIndex = sl.value.linlin(0, 1, 0, 20);
            fmIndexNum.string_(~fmIndex.round(0.1).asString);
        });
    fmIndexNum = StaticText(win, 50@20).string_(~fmIndex.round(0.1).asString);

    StaticText(win, 60@20).string_("Feedback");
    Slider(win, 200@20)
        .value_(~fmFeedback.linlin(0, 1, 0, 1))
        .action_({ |sl|
            ~fmFeedback = sl.value;
            fmFeedbackNum.string_((~fmFeedback * 100).round(1).asString ++ "%");
        });
    fmFeedbackNum = StaticText(win, 50@20).string_((~fmFeedback * 100).round(1).asString ++ "%");

    StaticText(win, 60@20).string_("Ratio Rnd");
    Slider(win, 200@20)
        .value_(0)
        .action_({ |sl|
            ~ratioRandom = sl.value.linlin(0, 1, 0, 2);
            fmRatioRndNum.string_(~ratioRandom.round(0.01).asString);
        });
    fmRatioRndNum = StaticText(win, 50@20).string_("0");

    StaticText(win, 60@20).string_("Bits");
    Slider(win, 200@20)
        .value_(~bits.linlin(1, 16, 0, 1))
        .action_({ |sl|
            ~bits = sl.value.linlin(0, 1, 1, 16).round(1);
            bitsNum.string_(~bits.asString);
        });
    bitsNum = StaticText(win, 50@20).string_(~bits.asString);

    win.view.decorator.nextLine;

    // FM Ratio presets
    StaticText(win, 50@18).string_("Ratios:").font_(Font("Helvetica", 10));
    [
        ["1:1", 1.0],      // Pure
        ["√2", 1.414],     // Metallic
        ["π", 3.14159],    // Inharmonic
        ["φ", 1.618],      // Golden
        ["7:4", 1.75]      // Bell-like
    ].do { |pair|
        Button(win, 48@18)
            .states_([[pair[0], Color.black, Color.gray(0.85)]])
            .font_(Font("Helvetica", 9))
            .action_({
                ~fmRatio = pair[1];
                ("Ratio: " ++ pair[0] ++ " = " ++ pair[1]).postln;
            });
    };

    win.view.decorator.nextLine;

    // === PLAY MODE ===
    StaticText(win, 320@15).string_("─── Play Mode ───").align_(\center);

    [\random, \forward, \backward, \pingpong].do { |mode|
        Button(win, 75@30)
            .states_([
                [mode.asString, Color.black, Color.gray(0.75)],
                [mode.asString, Color.white, Color.blue(0.6)]
            ])
            .value_(if(~playMode == mode) { 1 } { 0 })
            .action_({ |btn|
                ~playMode = mode;
                ~stepIndex = 0;
                ~pingpongDir = 1;
                ("Mode: " ++ mode).postln;
                // Update all mode buttons
                win.view.children.do { |child|
                    if(child.class == Button) {
                        if([\random, \forward, \backward, \pingpong].includes(child.states[0][0].asSymbol)) {
                            child.value_(if(child.states[0][0].asSymbol == mode) { 1 } { 0 });
                        };
                    };
                };
            });
    };

    win.view.decorator.nextLine;

    // === NOTE PRESETS ===
    StaticText(win, 320@15).string_("─── Note Presets ───").align_(\center);

    presets.keysValuesDo { |name, notes|
        Button(win, 90@28)
            .states_([[name.asString, Color.black, Color.gray(0.8)]])
            .action_({
                ~notes = notes;
                ~stepIndex = 0;
                customNoteField.string_(notes.asString);
                ("Notes: " ++ notes).postln;
            });
    };

    win.view.decorator.nextLine;

    // === CUSTOM NOTES ===
    StaticText(win, 320@15).string_("─── Custom Notes ───").align_(\center);

    StaticText(win, 320@15).string_("Enter MIDI notes (e.g. 60, 62, 64, 67):").font_(Font("Helvetica", 10));

    customNoteField = TextField(win, 240@25)
        .string_(~notes.asString)
        .action_({ |field|
            var str = field.string;
            var notes;
            // Parse comma or space separated numbers
            str = str.replace("[", "").replace("]", "");
            notes = str.split($,).collect({ |s| s.stripWhiteSpace.asInteger });
            notes = notes.select({ |n| n > 0 and: { n < 128 } });
            if(notes.size > 0) {
                ~notes = notes;
                ~stepIndex = 0;
                ("Custom notes: " ++ notes).postln;
            } {
                "Invalid notes!".postln;
            };
        });

    Button(win, 70@25)
        .states_([["Apply", Color.white, Color.blue(0.6)]])
        .action_({ customNoteField.doAction });

    win.view.decorator.nextLine;

    // === DISPLAY ===
    StaticText(win, 320@15).string_("─── Status ───").align_(\center);

    ~noteDisplay = StaticText(win, 320@20)
        .string_("Notes: " ++ ~notes.asString)
        .align_(\center)
        .background_(Color.gray(0.9));

    ~counterDisplay = RangeSlider(win, 320@15)
        .lo_(0).hi_(0)
        .enabled_(false);

    // Update displays
    ~guiUpdater = Routine({
        loop {
            {
                ~noteDisplay !? {
                    ~noteDisplay.string_("Notes: " ++ ~notes.asString ++ "  Step: " ++ ~stepIndex);
                };
                ~counterDisplay !? {
                    ~counterDisplay.hi_(~counter / ~crescendoLen);
                };
            }.defer;
            0.1.wait;
        };
    }).play(AppClock);

    // Cleanup
    win.onClose_({
        ~guiUpdater !? { ~guiUpdater.stop };
        "GUI closed".postln;
    });

}.value;
)
