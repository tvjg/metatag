var vows   = require('vows');
var should = require('should');
var join = require('path').join;
var fs = require('fs');

var ID3 = require('../lib/id3');
var Frame = require('../lib/id3/frame').Frame;

var empty = join('test','data','emptyfile.mp3');
var silence = join('test','data','silence-44-s.mp3');
var badsync = new Buffer('00ff00616200', 'hex');

vows
  .describe('ID3 Loading')
  .addBatch({
    'An ID3 wrapper ': {
      'loading an empty file': {
	topic: function () {
	  new ID3(empty, this.callback)
	},
	'should throw a no header error': function (err, id3) {
	  err.should.match(/too small/);
	}
      },
      'loading a file that doesn\'t exist': {
	topic: function () {
	  new ID3(join('path','does','not','exist'), this.callback)
	},
	'should throw ENOENT': function (err, id3) {
	  err.should.match(/ENOENT/);
	}
      },
      'loading an empty header ': {
	topic: function () {
	  var id3 = new ID3();
	  var context = {
	    fd       : fs.openSync(empty,'r'),
	    position : 0
	  };
	  id3.loadHeader(context).nodeify(this.callback);
	},
	'should throw an end of file error': function (err, id3) {
	  err.should.match(/end of file/i);
	}
      },
      'loading silent test data header ': {
	topic: function() {
	  var id3 = new ID3();
	  var context = {
	    fd       : fs.openSync(silence,'r'),
	    position : 0
	  };
	  id3.loadHeader(context).nodeify(this.callback);
	},
	'should read a minor revision of 3': function (err, id3) {
	  id3.version.minor.should.equal(3);
	},
	'should read a size of 1314 bytes': function (err, id3) {
	  id3.size.should.equal(1314);
	}
      },
      'loading no ID3 information': {
	topic: new ID3(),
	'should throw when attempting negative read': function (id3) {
	  (function() {
	    id3.fullRead({ fileSize: 0, position:0 }, -3);
	  }).should.throwError(/less than zero/i);
	},
	'should throw when attempting to read beyond file size': function (id3) {
	  (function() {
	    id3.fullRead({ fileSize: 0, position:0 }, 3);
	  }).should.throwError();
	}
      },
      'with an unsynchronization flag': {
	topic: function () {
	  var id3 = new ID3();
	  id3._flags = 0x80;
	  id3.loadFramedata(Frame.FRAMES['TPE2'], 0, badsync).nodeify(this.callback);
	},
	'should decode a value of \'\\xffab\'': function (err, frame) {
	  should.equal(frame, '\xffab');
	}
      },
      'with an unsynchronization flag on a frame': {
	topic: function () {
	  var id3 = new ID3();
	  id3._flags = 0x00;
	  id3.loadFramedata(Frame.FRAMES['TPE2'], 0x02, badsync).nodeify(this.callback);
	},
	'should decode a value of \'\\xfab\'': function (err, frame) {
	  should.equal(frame, '\xffab');
	}
      },
      'with no unsynchronization flag': {
	topic: function () {
	  var id3 = new ID3();
	  id3.loadFramedata(Frame.FRAMES['TPE2'], 0, badsync).nodeify(this.callback);
	},
	'should decode a value of \'[\'\\xff\',\'ab\']\'': function(err, tag) {
	  tag.text.should.eql(['\xff', 'ab']);
	}
      }

    }})
  .export(module);
