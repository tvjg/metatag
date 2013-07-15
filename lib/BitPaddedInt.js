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

  var numeric_value = 0, shift = 0;

  bytes.forEach(function(byte, idx) { 
    numeric_value += (byte * Math.pow(2, shift));
    shift += bits;
  });

  return numeric_value;
}
