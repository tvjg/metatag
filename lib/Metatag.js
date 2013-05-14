var ID3  = require('./ID3');

module.exports = Metatag;

function Metatag(filepath) {
  // TODO: Ultimately we want to doing some kind of file inspection, so that we
  // can choose the correct metadata format wrapper.
  return new ID3(filepath);
}
