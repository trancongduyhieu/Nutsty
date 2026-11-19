import QtQuick

// Quickshell's Scope is a plain QObject, not an Item. Keep it that way here:
// a Window nested in an Item becomes that Item's child window (Qt 6.7+), and
// with no parent window its declarative `visible` is never applied, so panels
// such as the desktop lyrics stayed hidden on Windows.
QtObject {
    id: root
    default property list<QtObject> childrenData
}
