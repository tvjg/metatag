BitPaddedInt = (value, bits = 7) ->
  mask = (1 << bits) - 1
  bytes = []

  for i in [0...value.length]
    byte = value.charAt(i)
    bytes.push(byte.charCodeAt(0) & mask)

  do bytes.reverse

  numeric_value = 0
  shift = 0

  bytes.forEach (byte) ->
    numeric_value += (byte * Math.pow(2, shift))
    shift += bits

  return numeric_value

module.exports = BitPaddedInt
