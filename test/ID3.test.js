var vows   = require('vows');
var should = require('should');
var rewire = require('rewire');

var ID3 = rewire('../lib/ID3.js');

vows.describe('ID3').addBatch({
  'An ID3 wrapper ': {
    topic: function(){
      ID3.__set__('fs', {
	readSync: function(fd, buff, offset, size, position) {
	  var headerLoads = {
	    'header22': '49443302000000000000',
	    'header21': '49443301000000000000',
	    'shortHeader': '494433010000000000',
	    'header24Extended': '49443304004000000000000000055a',
	    'header23Extended': '4944330300400000000000000006000056789abc', 
	  };

	  var testHeader = headerLoads[fd];
	  var b = new Buffer(testHeader,'hex');
         
          // Buffer.copy will throw if we overstep bounds
          // fs.readSync copies to end and return read size
          var endPos = position+size;
          if (endPos > b.length) {
            endPos = b.length;
            size = endPos - position;
          }
	  
          b.copy(buff, offset, position, endPos);
          return size;  
	}
      });

      return null;
    },

    'loading a v2.2 tag': {
      topic: function() {
	var id3 = new ID3();
	id3.__fileobj = 'header22';
	return id3;
      },
      'should have a major revision of 2': function(id3) {
	id3.loadHeader();
	id3.version.majorRev.should.equal(2); 
      }
    },
    
    'loading a v2.1 tag': {
      topic: function() {
	var id3 = new ID3();
	id3.__fileobj = 'header21';
	return id3;
      },
      'should throw a not supported error': function(id3) {
	(function() {
	  id3.loadHeader()
	}).should.throwError(/not supported/);
      }
    },

    'loading a truncated header': {
      topic: function() {
	var id3 = new ID3();
	id3.__fileobj = 'shortHeader';
	return id3;
      },
      'should throw an end of file error': function(id3) {
	(function() {
	  id3.loadHeader();
	}).should.throwError(/end of file/i);
      }
    },

    'loading a v2.4 extended header': {
      topic: function() {
	var id3 = new ID3();
	id3.__fileobj = 'header24Extended';
	id3.loadHeader();
	return id3;
      },
      'should have a size of 1 byte': function(id3) {
	id3.__extsize.should.eql(1);
      },
      'should have a data value of 5A': function(id3) {
	id3.__extdata.should.eql('5a');
      }
    },

    'loading a v2.3 extended header': {
      topic: function() {
	var id3 = new ID3();
	id3.__fileobj = 'header23Extended';
	id3.loadHeader();
	return id3;
      },
      'should have a size of 6 bytes': function(id3) {
	id3.__extsize.should.eql(6);
      },
      'should have a data value of 00 00 56 78 9A BC': function(id3) {
	id3.__extdata.should.eql('000056789abc');
      }
    },
    teardown: function() { rewire.reset(); }
  }
}).export(module);
