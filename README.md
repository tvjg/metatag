metatag
=======
metatag is a library for parsing audio metadata formats like ID3. It also
provides a small CLI utility for inspecting audio metadata.

metatag is inspired by the wonderful
[Mutagen](https://code.google.com/p/mutagen/) library. For the moment,
development is exclusively focused on reading metadata, not writing or updating
it. Additionally, it will strive to comply with the Mutagen's extensive test
suite.

Installation
------------
Install via npm:

```
npm install metatag
```

Supported Formats
-----------------
* ID3 (v1.1, v2.2, v2.3, v2.4)

Stability
---------
Unstable: Expect patches, features, and API changes.

That said, this module works well for reading ID3 tags. It has over 350 unit
tests and hasn't choked on any of the MP3s I've captured in the wild.

Todo
----
* More complete support for all ID3 frames
* Cleanup TODO comments
* Investigate higher level parsing methods ie streams of tokens
* Support for other metadata formats
* Fallback for unsupported text encodings
* Clientside support
* Accept file readstream instead of opening file
* Support advanced ID3 features like encryption?
* Write support?
* Make various tag formats into git submodules under the main metatag interface
* Ditch flatiron (in favor of lighter cli option) and sprintf requirements

See Also
--------
There are a number of other Javascript ID3 parsing solutions in varying states
of completion. Here is a partial list:

* <https://github.com/antimatter15/js-id3v2>
* <https://github.com/aadsm/JavaScript-ID3-Reader>
* <https://github.com/francescomari/id3>
* <https://github.com/leetreveil/node-musicmetadata>
