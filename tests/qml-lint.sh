#!/bin/bash

set -euo pipefail

# Supply the singleton qmldir metadata explicitly. Quickshell maps these
# modules through its synthetic `qs` namespace at runtime; standalone Qt
# tooling otherwise reports every native shell token as missing.
/usr/lib/qt6/bin/qmllint \
  -i /usr/share/omarchy/shell/Ui/qmldir \
  -i /usr/share/omarchy/shell/Commons/qmldir \
  --prefer-non-var-properties disable \
  ./*.qml
