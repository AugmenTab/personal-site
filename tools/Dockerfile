# Development-only tooling image (never part of the site build or CI):
#   - screenshots/: browser screenshots and checks (Playwright + Chromium)
#   - art/: reconstruction of the hero plates from the owner's approved render
#     (text/UI removal by inpainting, plate cutting), emblem preparation, and
#     comparison sheets (NumPy, SciPy, Pillow, OpenCV; Chromium rasterises SVG)
#
# The base image ships matching Chromium builds; the Python binding is pinned
# to the same version. All Python packages are pinned.
FROM mcr.microsoft.com/playwright/python:v1.49.1-noble

RUN pip install --no-cache-dir --break-system-packages \
      playwright==1.49.1 \
      numpy==2.1.3 \
      scipy==1.14.1 \
      pillow==11.0.0 \
      opencv-python-headless==4.10.0.84

# Phase 06: axe-core, the accessibility rules engine, injected into pages by
# tools/screenshots/phase06.py (never served by the site). Pinned version.
ADD https://unpkg.com/axe-core@4.10.2/axe.min.js /opt/axe/axe.min.js
RUN chmod 0644 /opt/axe/axe.min.js
