import QtQuick

// Material 3 Expressive Spatial Spring Animation
// Tuned for natural organic squish, overshoot, and snappy settle.
// Reference: Swiftify Bounce.qml { spring: 7; damping: 0.24; epsilon: 0.002 }
SpringAnimation {
    id: springAnim
    spring: 7
    damping: 0.24
    epsilon: 0.002
}
