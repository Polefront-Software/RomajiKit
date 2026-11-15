# Third-party notices for RomajiKit

RomajiKit is built on the following. MeCab is built into an app that uses the package; the dictionary is in the
pack the app fetches (`scripts/romaji-dictionary.sh` builds it):

| What | From | Licence |
|---|---|---|
| MeCab, the morphological analyzer | Taku Kudo; Nippon Telegraph and Telephone Corporation | BSD (chosen from GPL / LGPL / BSD) |
| IPA dictionary (mecab-ipadic), compiled with only the fields RomajiKit reads | Nara Institute of Science and Technology; entries from ICOT Free Software | NAIST / ICOT terms |
| Mecab-Swift, the Swift package that carries both | telethon k.k. (Morten Bertz) | MIT |

The IPAdic terms ask that the copyright notice and the two paragraphs after it, and the
ICOT "NO WARRANTY" section, go with every copy. The full texts are in
`Sources/RomajiKit/Resources/ThirdPartyNotices.txt`, which is built into the app and shown
under Settings, so every copy of the app carries them. The pack carries IPAdic's own
`COPYING` beside the dictionary, so every copy of the dictionary does too.

RomajiKit's own lists (`exceptions.json`, `gikun-hints.json`) are RomajiKit's own work.
