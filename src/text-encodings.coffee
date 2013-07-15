Iconv = require('iconv').Iconv

{UnicodeDecodeError} = require './errors'

decode = 
  latin1  : new Iconv 'ISO-8859-1','UTF-8'
  utf16   : new Iconv 'UTF-16','UTF-8'
  utf16be : new Iconv 'UTF-16BE','UTF-8'
  utf8    : { convert: (buffer) -> buffer }

convert = (buffer) ->
  { 
    from: (encoding) ->  
      convert = decode[encoding]?.convert
      throw new UnicodeDecodeError "Conversion from #{encoding} unsupported" unless convert 

      try
        (convert buffer).toString()
      catch err
        throw new UnicodeDecodeError (err.message || err)
  }

module.exports = convert
