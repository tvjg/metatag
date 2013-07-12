ID3 = require './id3';

## TODO: Ultimately we want to doing some kind of file inspection, so that we
## can choose the correct metadata format wrapper.
class Metatag
  constructor: (filepath) -> return new ID3(filepath)

module.exports = Metatag;
