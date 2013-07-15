{ValueError} = require '../errors'

unsynch = 
  decode: (buffer) ->
    hexVal = buffer.toString('hex')
    output = []
    safe = true

    for first,idx in hexVal by 2
      couplet = (first + hexVal[idx + 1])
      if safe
        output.push(couplet)
        safe = (couplet != 'ff')
      else
        if couplet >= 'e0' 
          throw new ValueError 'invalid sync-safe string'
        else if couplet != '00' 
          output.push(couplet)
        safe = true
    
    throw new ValueError 'string ended unsafe' unless safe
    
    new Buffer(output.join(''), 'hex')

module.exports = unsynch
