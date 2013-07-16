metatag
=======

metatag is a [Mutagen](https://code.google.com/p/mutagen/) inspired library written in Coffeescript for parsing audio metadata formats like ID3. In the beginning at least, it will strive for compliance with the extensive Mutagen test suite. It also provides a small CLI utility for inspecting audio metadata. For the moment, development is exclusively focused on reading metadata, not writing or updating it.

Installation
------------
Install via npm:

```
npm install metatag
```

Supported Formats
-----------------
* ID3 (v1.1, v2.2, v2.3, v2.4)

Todo
----

* More complete support for all ID3 frames
* Support advanced ID3 features like frame compression
* Cleanup TODO comments
* Investigate higher level parsing methods ie streams of tokens
* Support for other metadata formats
* Clientside support
* Accept file readstream instead of opening file
* Write support?

See Also
--------

There are a number of other Javascript ID3 parsing solutions in varying states of completion. Here is a partial list:

* <https://github.com/antimatter15/js-id3v2>
* <https://github.com/aadsm/JavaScript-ID3-Reader>
* <https://github.com/francescomari/id3>
* <https://github.com/leetreveil/node-musicmetadata>

#### Author: [John Guidry](http://github.com/dirtyrottenscoundrel)
