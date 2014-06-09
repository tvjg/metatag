var vows   = require('vows');
var should = require('should');
var rewire = require('rewire');

var ID3    = require('../lib/id3');
var Parser = rewire('../lib/id3/parser');

Parser.__set__('fs', {
  read: function(fd, buff, offset, size, position, cb) {
    var headerLoads = {
      'header22'                  : '49443302000000000000',
      'header21'                  : '49443301000000000000',
      'shortHeader'               : '494433010000000000',
      'header24Extended'          : '49443304004000000000000000055a',
      'header23Extended'          : '4944330300400000000000000006000056789abc',
      'header24AllowFooter'       : '49443304001000000000',
      'header24ExtendedButNot'    : '49443304004000000000544954310000000161',
      'header24ExtendedButNotTag' : '4944330400400000000054495439'
    };

    var testHeader = headerLoads[fd];
    var b = new Buffer(testHeader,'hex');

    // Buffer.copy will throw if we overstep bounds
    // fs.read copies to end and return read size
    var endPos = position+size;
    if (endPos > b.length) {
      endPos = b.length;
      size = endPos - position;
    }

    b.copy(buff, offset, position, endPos);
    cb(null, size, buff);
  }
});

vows
  .describe('ID3 Header')
  .addBatch({
    'An ID3 wrapper ': {
      'loading a v2.2 tag header': {
	topic: function () {
	  var id3 = new ID3();
	  var context = { fd:'header22', position:0 };
          var parser = new Parser(id3, context);
	  parser.loadHeader().nodeify(this.callback);
	},
	'should have a minor revision of 2': function (err, id3) {
	  id3.version.minor.should.equal(2);
	}
      },

      'loading a v2.1 tag header': {
	topic: function () {
	  var id3 = new ID3();
	  var context = { fd:'header21', position:0 };
          var parser = new Parser(id3, context);
	  parser.loadHeader().nodeify(this.callback);
	},
	'should throw a not supported error': function (err, id3) {
	  err.message.should.match(/not supported/);
	}
      },

      'loading a truncated header': {
	topic: function () {
	  var id3 = new ID3();
	  var context = { fd:'shortHeader', position:0 };
          var parser = new Parser(id3, context);
	  parser.loadHeader().nodeify(this.callback);
	},
	'should throw an end of file error': function (err, id3) {
	  err.message.should.match(/end of file/i);
	}
      },

      'loading a v2.4 extended header': {
	topic: function () {
	  var id3 = new ID3();
	  var context = { fd:'header24Extended', position:0 };
          var parser = new Parser(id3, context);
	  parser.loadHeader().nodeify(this.callback);
	},
	'should have a size of 1 byte': function (err, id3) {
	  id3.extSize.should.eql(1);
	},
	'should have a data value of 5A': function (err, id3) {
	  id3.extData.should.eql(new Buffer('5a','hex'));
	}
      },

      'loading a v2.3 extended header': {
	topic: function () {
	  var id3 = new ID3();
	  var context = { fd:'header23Extended', position:0 };
          var parser = new Parser(id3, context);
	  parser.loadHeader().nodeify(this.callback);
	},
	'should have a size of 6 bytes': function (err, id3) {
	  id3.extSize.should.eql(6);
	},
	'should have a data value of 00 00 56 78 9A BC': function (err, id3) {
	  id3.extData.should.eql(new Buffer('000056789abc','hex'));
	}
      },

      'loading a v2.4 header': {
	topic: function () {
	  var id3 = new ID3();
	  var context = { fd:'header24AllowFooter', position:0 };
          var parser = new Parser(id3, context);
	  parser.loadHeader().nodeify(this.callback);
	},
	'should allow a footer': function (err, id3) {
	  id3.f_footer.should.eql(true);
	}
      },

      'loading a v2.4 extended header containing a tag in extData': {
	topic: function () {
	  var id3 = new ID3();
	  var context = { fd:'header24ExtendedButNot', position:0 };
          var parser = new Parser(id3, context);
	  parser.loadHeader().nodeify(this.callback);
	},
	'should yield an extended size of 0': function (err, id3) {
	  id3.extSize.should.eql(0);
	},
	'and no extended data': function (err, id3) {
	  id3.extData.should.eql(new Buffer(''));
	}
      },

      'loading a v2.4 extended header but no tag in extData': {
	topic: function () {
	  var id3 = new ID3();
	  var context = { fd:'header24ExtendedButNotTag', position:0 };
          var parser = new Parser(id3, context);
	  parser.loadHeader().nodeify(this.callback);
	},
	'should throw an end of file error': function (err, id3) {
	  err.message.should.match(/end of file/i);
	}
      }

    }})
  .export(module);
