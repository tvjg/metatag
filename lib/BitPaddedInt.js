var _ = require('underscore');

module.exports = BitPaddedInt;

function BitPaddedInt(value, bits) {
  bits = bits || 7;
  var mask = (1	<< bits) - 1;
  var bytes = [];

  for (var i = 0; i < value.length; i++) {
    var byte = value.charAt(i);
    bytes.push(byte.charCodeAt(0) & mask);
  }
  bytes.reverse();

  var numeric_value = 0;
  var byte_offsets = _.range(0, (bytes.length)*bits, bits);
  _.each(_.zip(byte_offsets, bytes), function(el) { 
    var shift = el[0];
    var byte = el[1];
    
    numeric_value += (byte * Math.pow(2, shift));
  });

  return numeric_value;
}
