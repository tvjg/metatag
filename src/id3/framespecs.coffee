sprintf = require("sprintf-js").sprintf

convert = require '../text-encodings'

{ValueError, UnicodeDecodeError} = require '../errors'

# Utility functions
isString = (a) -> Object.prototype.toString.call(a) == "[object String]"
isArray = require('util').isArray

class Spec
  constructor: (name) ->
    return new Spec(arguments...) unless this instanceof Spec
    @name = name

class ByteSpec extends Spec
  constructor: (name) ->
    return new ByteSpec(arguments...) unless this instanceof ByteSpec
    super name

  read: (frame, data) ->
    #TODO: Take a closer look at what we're doing here
    [ data.toString('utf8', 0, 1).charCodeAt(0), data[1..] ]
    ## return ord(data[0]), data[1:]

  validate: (frame, value) -> value

class EncodingSpec extends ByteSpec
  constructor: (name) ->
    return new EncodingSpec(arguments...) unless this instanceof EncodingSpec
    super name

  read: (frame, data) ->
    [enc, data] = super arguments...
    return [enc, data] if enc < 16

    chr = new Buffer(String.fromCharCode(enc), 'utf8')
    return [ 0, Buffer.concat([chr, data]) ]

  validate: (frame, value) ->
    if 0 <= value <= 3 then return value
    if !value then return null
    throw new ValueError "Invalid Encoding: #{value}"

class StringSpec extends Spec
  constructor: (name, length) ->
    return new StringSpec(arguments...) unless this instanceof StringSpec

    @len = length
    super name

  read: (frame, data) ->
    [ (convert data[...@len]).from('latin1'), data[@len..] ]

  validate: (frame, value) ->
    return null unless value?

    return value if isString(value) and value.length == @len

    throw new ValueError sprintf('Invalid StringSpec[%d] data: %s', @len, value)

class MultiSpec extends Spec
  constructor: (name, specs..., sep) ->
    if this not instanceof MultiSpec
      ## Need a throwaway arg for applying to bind
      Array.prototype.unshift.call(arguments, null)
      return new (Function.prototype.bind.apply(MultiSpec, arguments))

    @specs = specs
    #TODO: Separator used in validate for mutagen?
    @sep = sep
    super name

  read: (frame, data) ->
    values = []

    while data.length
      record = []
      for spec in @specs
        [value, data] = spec.read(frame, data)
        record.push value

      if @specs.length isnt 1 then values.push record
      else values.push record[0]

    return [values, data]

  validate: (frame, value) ->
    if !value then return []
    if @sep and isString(value)
      value = value.split(@sep)
    if isArray(value)
      if @specs.length is 1
        return (@specs[0].validate(frame, v) for v in value)
      #TODO:
      #else
        #return [
          #[s.validate(frame, v) for (v,s) in zip(val, @specs)]
          #for val in value ]
      throw new ValueError "Invalid MultiSpec data: #{value}"

class BinaryDataSpec extends Spec
  constructor: (name) ->
    return new BinaryDataSpec(arguments...) unless this instanceof BinaryDataSpec
    super name

  read: (frame, data) -> [data, '']

  validate: (frame, value) -> value.toString()  #TODO: Unsure about this

class EncodedTextSpec extends Spec

  @_encodings = [
    [ 'latin1'  , '00' ],
    [ 'utf16'   , '0000' ],
    [ 'utf16be' , '0000' ],
    [ 'utf8'    , '00' ]
  ]

  constructor: (name) ->
    return new EncodedTextSpec(arguments...) unless this instanceof EncodedTextSpec
    super name

  read: (frame, data) ->
    [encoding, term] = EncodedTextSpec._encodings[frame.encoding]

    hexStr = data.toString 'hex'
    grouping = if term.length is 2 then /(.{2})/g else /(.{4})/g
    hexArr = hexStr.match grouping

    ret = ''
    offset = hexArr.indexOf term
    if offset isnt -1
      stringOffset = offset * term.length
      [data, ret] = [ hexStr[0...stringOffset], hexStr[stringOffset+term.length..] ]

    data = new Buffer(data, 'hex') if typeof data is 'string'
    ret = new Buffer(ret, 'hex')

    if data.length < (term.length / 2) then return ['', ret]

    return [(convert data).from(encoding), ret]

  validate: (frame, value) -> value

#TODO: Since I used that cute constructor override trick to avoid calling new,
# I've created a different potential problem. In the event, I don't override the
# subclass constructor the object will be new-ed as a different type by the
# first overriden parent constructor. Either override all constructors in the
# inheritance chain or find some kind of functional craziness to dynamically
# invoke the correct constructor.
#
# Example:
#  console.log (EncodedNumericTextSpec('caca') instanceof EncodedNumericTextSpec)
#  console.log (EncodedNumericTextSpec('caca') instanceof EncodedTextSpec)
#
class EncodedNumericTextSpec extends EncodedTextSpec
class EncodedNumericPartTextSpec extends EncodedTextSpec

class Latin1TextSpec extends EncodedTextSpec
  constructor: (name) ->
    return new Latin1TextSpec(arguments...) unless this instanceof Latin1TextSpec
    super name

  read: (frame, data) ->
    hexStr = data.toString 'hex'
    hexArr = hexStr.match /(.{2})/g

    ret = ''
    offset = hexArr.indexOf '00'
    if offset isnt -1
      stringOffset = offset * 2
      [data, ret] = [ hexStr[0...stringOffset], hexStr[stringOffset+2..] ]

    data = new Buffer(data, 'hex')
    ret = new Buffer(ret, 'hex')

    return [(convert data).from('latin1'), ret]

  validate: (frame, value) -> value

## A time stamp in ID3v2 format.

## This is a restricted form of the ISO 8601 standard; time stamps
## take the form of:
##     YYYY-MM-DD HH:MM:SS
## Or some partial form (YYYY-MM-DD HH, YYYY, etc.).
##
## The 'text' attribute contains the raw text data of the time stamp.
##
class ID3TimeStamp

  formats = ['%04d', '%02d', '%02d', '%02d', '%02d', '%02d']
  seps = ['-', '-', ' ', ':', ':', 'x']

  # parseInt allows some garbage that doesn't fly with Python's int. For
  # example, '12.aW123' will be truncated and coerced to a number. NaN is only
  # returned if first character cannot be converted to a number. This regex
  # from the MDN tightens things up a bit.
  strictInt = /^\-?([0-9]+|Infinity)$/

  #TODO: Mutagen allows overriding regex
  splitre = /[-T:/.]|\s+/

  constructor: (text) ->

    Object.defineProperty this, 'text',
      enumerable: true
      get: () ->
        parts = [ @year, @month, @day, @hour, @minute, @second ]
        pieces = []
        for part,idx in parts when part isnt null
          pieces.push(sprintf(formats[idx], part) + seps[idx])
        pieces.join('')[...-1]

      set: (text) ->
        [ year, month, day, hour, minute, second ] =
          (text + ':::::').split(splitre)[...6]
        values = { year, month, day, hour, minute, second }

        for unit,v of values
          v = parseInt(v, 10)
          v = null if Number.isNaN(v) or not strictInt.test(v)
          this[unit] = v

    text = text.text if text instanceof ID3TimeStamp
    @text = text

  toString: () -> @text

  valueOf: () -> @text

class TimeStampSpec extends EncodedTextSpec
  constructor: (name) ->
    return new TimeStampSpec(arguments...) unless this instanceof TimeStampSpec
    super name

  read: (frame, data) ->
    [ value, data ] = super arguments...
    return [ @validate(frame, value), data ]

  validate: (frame, value) ->
    try
      return new ID3TimeStamp(value)
    catch err
      throw new ValueError "Invalid ID3TimeStamp: #{value}"

module.exports = {
  Spec
  ByteSpec
  EncodingSpec
  StringSpec
  MultiSpec
  BinaryDataSpec
  EncodedTextSpec
  EncodedNumericTextSpec
  EncodedNumericPartTextSpec
  Latin1TextSpec
  ID3TimeStamp
  TimeStampSpec
}
