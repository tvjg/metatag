var path = require('path');
var ID3  = require('./ID3');

module.exports = Metatag;

function Metatag(filepath) {
  var id3 = new ID3(filepath);
  console.log(id3);
}
