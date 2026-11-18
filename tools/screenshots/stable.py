"""Deterministic screenshot mode (Phase 06).

Static captures used to differ from run to run because some were taken
while a CSS transition (the compact index caret, a chip's tint, a focus
colour) was still running. This module removes every source of timing
noise a static capture can see, **in the test browser only**:

  - fixed viewport, device scale factor 1, locale, time zone, colour scheme
    and motion preference (``CONTEXT``);
  - every transition and animation is cut to its end state, smooth
    scrolling is off and the text caret is hidden (``FREEZE_CSS``, injected
    as a stylesheet into the page under test; nothing in ``assets/`` or
    ``dist/`` changes);
  - lazy images are loaded, every image is decoded and every font face is
    loaded before the capture (observable readiness, not sleeps);
  - two animation frames are awaited so style and layout have settled.

Actual motion (transitions present by default, removed under reduced
motion, no perpetual animation) is tested separately by phase06.py, never
through this mode.
"""

FREEZE_CSS = """
*, *::before, *::after {
  transition-duration: 0s !important;
  transition-delay: 0s !important;
  animation-duration: 0s !important;
  animation-delay: 0s !important;
  animation-iteration-count: 1 !important;
  caret-color: transparent !important;
}
html { scroll-behavior: auto !important; }
"""

# Stable browser settings for every deterministic context.
CONTEXT = {
    "device_scale_factor": 1,
    "locale": "en-US",
    "timezone_id": "UTC",
    "color_scheme": "dark",
    "reduced_motion": "no-preference",
}

SETTLE_JS = """
async (freezeCss) => {
  if (!document.getElementById('__stable_freeze')) {
    const style = document.createElement('style');
    style.id = '__stable_freeze';
    style.textContent = freezeCss;
    document.head.appendChild(style);
  }
  document.querySelectorAll('img[loading="lazy"]').forEach(i => { i.loading = 'eager'; });
  await document.fonts.ready;
  await Promise.all([...document.fonts].filter(f => f.status !== 'unloaded').map(f => f.loaded.catch(() => null)));
  await Promise.all([...document.images].map(i =>
    (i.complete ? Promise.resolve() : new Promise(r => { i.addEventListener('load', r, { once: true }); i.addEventListener('error', r, { once: true }); }))
      .then(() => (i.decode ? i.decode().catch(() => null) : null))));
  // Any animation still registered is finished, so it shows its end state.
  for (const a of document.getAnimations()) { try { a.finish(); } catch (e) { /* infinite: cancelled below */ a.cancel(); } }
  await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
}
"""


SCROLL_SETTLED_JS = """
async () => {
  // Resolves once the scroll position has not changed for 6 frames (a
  // smooth scroll has finished), or after 3 s.
  let last = -1, still = 0;
  const start = performance.now();
  while (still < 6 && performance.now() - start < 3000) {
    await new Promise(r => requestAnimationFrame(r));
    if (scrollY === last) still += 1; else { still = 0; last = scrollY; }
  }
}
"""


def scroll_settled(page):
    """Wait for real (possibly smooth) scrolling to stop: an observable
    condition instead of a fixed sleep. Leaves motion untouched."""
    page.evaluate(SCROLL_SETTLED_JS)


FREEZE_SYNC_JS = """
(freezeCss) => {
  if (!document.getElementById('__stable_freeze')) {
    const style = document.createElement('style');
    style.id = '__stable_freeze';
    style.textContent = freezeCss;
    document.head.appendChild(style);
  }
  for (const a of document.getAnimations()) { try { a.finish(); } catch (e) { a.cancel(); } }
  return true;
}
"""


# True when the page runs scripts. The HTML parser treats <noscript>
# content as markup only when scripting is disabled, so this is a
# synchronous probe that needs no timers or animation frames.
SCRIPTING_JS = """() => { const d = document.createElement('div');
  d.innerHTML = '<noscript><i></i></noscript>';
  return d.querySelector('i') === null; }"""


def settle(page):
    """Freeze motion and wait for fonts and decoded images. Idempotent.

    In a context with JavaScript disabled, Playwright can still run
    synchronous code, but a promise that awaits the page (fonts, decoding,
    animation frames) may never resolve: an unattended full run once hung
    there for hours. Such pages are detected synchronously first; the
    freeze is applied synchronously and readiness is the network going idle
    (the page has no scripts that could change it afterwards)."""
    if not page.evaluate(SCRIPTING_JS):
        page.wait_for_load_state("networkidle")
        page.evaluate(FREEZE_SYNC_JS, FREEZE_CSS)
        return
    page.evaluate(SETTLE_JS, FREEZE_CSS)


def new_context(browser, viewport, **overrides):
    options = dict(CONTEXT, viewport=viewport)
    options.update(overrides)
    return browser.new_context(**options)
