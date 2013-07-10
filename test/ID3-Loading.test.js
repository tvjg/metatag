var vows   = require('vows');
var should = require('should');
var rewire = require('rewire');
var join = require('path').join;
var fs = require('fs');

var ID3 = rewire('../lib/ID3.js');
var Frame = require('../lib/Frame.js');

var empty = join('test','data','emptyfile.mp3');
var silence = join('test','data','silence-44-s.mp3');
var badsync = new Buffer('00ff00616200', 'hex');

vows
  .describe('ID3 Loading')
  .addBatch({
    'An ID3 wrapper ': {
      'loading an empty file': {
        topic: (new ID3()),
        'should throw a no header error': function(id3) {
          (function(){
            id3.load(empty);
          }).should.throwError(/too small/);
        }
      },
      'loading a file that doesn\'t exist': {
        topic: (new ID3()),
        'should throw a no such file error ': function(id3) {
          (function() {
            id3.load(join('path','does','not','exist'));
          }).should.throwError(/no such file/);
        }
      },
      'loading an empty header ': {
        topic: function() {
          var id3 = new ID3();
          id3._fd = fs.openSync(empty,'r');
          return id3;
        },
        'should throw an end of file error': function(id3) {
          (function() {
            id3.loadHeader();
          }).should.throwError(/end of file/i);
        }
      },
      'loading silent test data header ': {
        topic: function() {
          var id3 = new ID3();
          id3._fd = fs.openSync(silence,'r');
          id3.loadHeader();
          return id3;
        },
        'should read a minor revision of 3': function(id3) {
          id3.version.minor.should.equal(3);
        },
        'should read a size of 1314 bytes': function(id3) {
          id3.size.should.equal(1314);
        }
      },
      'loading no ID3 information': {
        topic: function() {
          var id3 = new ID3();
          id3._fileSize = 0;
          return id3;
        },
        'should throw when attempting negative read': function(id3) {
          (function() {
            id3.fullRead(-3);
          }).should.throwError(/less than zero/i);
        },
        'should throw when attempting to read beyond file size': function(id3) {
          (function() {
            id3.fullRead(3);
          }).should.throwError();
        }
      },
      'with an unsynchronization flag': {
        topic: new ID3(),
        'should decode a value of \'\\xffab\'': function(id3) {
          id3._flags = 0x80;
          should.equal(
            id3.loadFramedata(Frame.FRAMES['TPE2'], 0, badsync), '\xffab');
        }
      },
      'with an unsynchronization flag on a frame': {
        topic: new ID3(),
        'should decode a value of \'\\xfab\'': function (id3) {
          id3._flags = 0x00;
          should.equal(
            id3.loadFramedata(Frame.FRAMES['TPE2'], 0x02, badsync), '\xffab');
        }
      },
      'with no unsynchronization flag': {
        topic: new ID3(),
        'should decode a value of \'[\'\\xff\',\'ab\']\'': function(id3) {
          tag = id3.loadFramedata(Frame.FRAMES["TPE2"], 0, badsync);
          tag.text.should.eql(['\xff', 'ab']);
        }
      }

    }})
  .addBatch({
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
              'header24AllowFooter': '49443304001000000000',
              'header24ExtendedButNot': '49443304004000000000544954310000000161',
              'header24ExtendedButNotTag': '4944330400400000000054495439'
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
          id3._fd = 'header22';
          return id3;
        },
        'should have a minor revision of 2': function(id3) {
          id3.loadHeader();
          id3.version.minor.should.equal(2);
        }
      },

      'loading a v2.1 tag': {
        topic: function() {
          var id3 = new ID3();
          id3._fd = 'header21';
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
          id3._fd = 'shortHeader';
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
          id3._fd = 'header24Extended';
          id3.loadHeader();
          return id3;
        },
        'should have a size of 1 byte': function(id3) {
          id3._extSize.should.eql(1);
        },
        'should have a data value of 5A': function(id3) {
          id3._extData.should.eql('5a');
        }
      },

      'loading a v2.3 extended header': {
        topic: function() {
          var id3 = new ID3();
          id3._fd = 'header23Extended';
          id3.loadHeader();
          return id3;
        },
        'should have a size of 6 bytes': function(id3) {
          id3._extSize.should.eql(6);
        },
        'should have a data value of 00 00 56 78 9A BC': function(id3) {
          id3._extData.should.eql('000056789abc');
        }
      },

      'loading a v2.4 header': {
        topic: function() {
          var id3 = new ID3();
          id3._fd = 'header24AllowFooter';
          return id3;
        },
        'should allow a footer': function(id3) {
          id3.loadHeader();
          id3.f_footer.should.eql(true);
        }
      },

      'loading a v2.4 extended header containing a tag in extData': {
        topic: function() {
          var id3 = new ID3();
          id3._fd = 'header24ExtendedButNot';
          id3.loadHeader();
          return id3;
        },
        'should yield an extended size of 0': function(id3) {
          id3._extSize.should.eql(0);
        },
        'and no extended data': function(id3) {
          id3._extData.should.eql('');
        }
      },

      'loading a v2.4 extended header but no tag in extData': {
        topic: function() {
          var id3 = new ID3();
          id3._fd = 'header24ExtendedButNotTag';
          return id3;
        },
        'should throw an end of file error': function(id3) {
          (function() {
            id3.loadHeader();
          }).should.throwError(/end of file/i);
        }
      }

    }})
  .export(module);
