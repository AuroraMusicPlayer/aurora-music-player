package dev.aurora.aurora_music

import com.ryanheise.audioservice.AudioServiceActivity

// AudioServiceActivity (not FlutterActivity) is required so media buttons and
// the Android Auto / notification session talk to the running Flutter engine.
class MainActivity : AudioServiceActivity()
