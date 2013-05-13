Iconv = require('iconv').Iconv

decode = 
  latin1  : new Iconv 'ISO-8859-1','UTF-8'
  utf16   : new Iconv 'UTF-16','UTF-8'
  utf16be : new Iconv 'UTF-16BE','UTF-8'
  utf8    : { convert: (buffer) -> buffer }

convert = (buffer) ->
  { 
    from: (encoding) ->  
      convert = decode[encoding]?.convert
      throw new Error "Conversion from #{encoding} unsupported" unless convert 

      (convert buffer).toString()
  }

module.exports = convert
