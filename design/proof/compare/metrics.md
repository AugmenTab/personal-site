# Registered comparison metrics

Mean absolute luminance difference (0-255) between the approved render
at 1440x900 and the proof screenshot. Lower is closer. These numbers
support visual judgment; they do not replace it.

## Artwork-only regions

| Region | Box (x0,y0,x1,y1) | MAD |
| --- | --- | --- |
| left architecture (beside text) | (0, 60, 300, 330) | 2.1 |
| left architecture (beside panel) | (0, 330, 140, 720) | 4.5 |
| right architecture (beside text) | (1150, 60, 1440, 330) | 2.1 |
| right architecture (beside panel) | (1300, 330, 1440, 720) | 4.2 |
| left cloud bank | (150, 165, 420, 290) | 2.0 |
| right cloud bank | (1060, 200, 1300, 300) | 2.3 |
| eclipse corona (above name) | (520, 50, 920, 100) | 12.5 |

## Regions with intentional content differences

(Different nav items, the role line, added CTAs, a static teaser instead
of the fake compiler. Not a fidelity score for the artwork.)

| Region | Box | MAD |
| --- | --- | --- |
| full frame | (0, 0, 1440, 900) | 14.9 |
| hero text band | (300, 100, 1140, 330) | 19.0 |
| CTA band + teaser | (140, 330, 1300, 900) | 19.6 |
