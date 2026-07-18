#!/bin/sh
# Fetches the on-device object-detection model (not committed: 59 MB).
# Apple Core ML model gallery, YOLOv3 with built-in NMS pipeline.
set -e
cd "$(dirname "$0")"
curl --retry 5 --retry-all-errors -C - -o Sources/YOLOv3Int8LUT.mlmodel \
  https://ml-assets.apple.com/coreml/models/Image/ObjectDetection/YOLOv3/YOLOv3Int8LUT.mlmodel
