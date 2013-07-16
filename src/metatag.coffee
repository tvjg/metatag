ID3 = require './id3';

## TODO: Ultimately we want to doing some kind of file inspection, so that we
## can choose the correct metadata format wrapper.
class Metatag
  constructor: (filepath, callback) -> return new ID3(arguments...)

module.exports = Metatag;
