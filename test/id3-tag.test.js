util = require('util');

vows   = require('vows');
should = require('should');

ID3   = require('../lib/id3');
Frame = require('../lib/id3/frame').Frame;

_23 = new ID3(); _23.version = { major: 2, minor: 3, sub: 0 }

var frameTestBatch = {};

[
  [ 'TALB' , '00612f62'             , 'a/b'       , null  , {encoding:0}] ,
  [ 'TBPM' , '00313230'             , '120'       , 120   , {encoding:0}] ,
  [ 'TCMP' , '0031'                 , '1'         , 1     , {encoding:0}] ,
  [ 'TCMP' , '0030'                 , '0'         , 0     , {encoding:0}] ,
  [ 'TCOM' , '00612f62'             , 'a/b'       , null  , {encoding:0}] ,
  [ 'TCON' , '0028323129446973636f' , '(21)Disco' , null  , {encoding:0}] ,
  [ 'TCOP' , '00313930302063'       , '1900 c'    , null  , {encoding:0}] ,
  [ 'TDAT' , '00612f62'             , 'a/b'       , null  , {encoding:0}] ,
  [ 'TDEN' , '0031393837'           , '1987'      , null  , {encoding:0, year:[1987]}] ,
  [ 'TDOR' , '00313938372d3132'     , '1987-12'   , null  , {encoding:0, year:[1987], month:[12]}] ,
  [ 'TDRC' , '003139383700'         , '1987'      , null  , {encoding:0, year:[1987]}] ,
  [ 'TDRL' , '00313938370031393838' , '1987,1988' , null  , {encoding:0, year:[1987, 1988]}] ,
  [ 'TDTG' , '0031393837'           , '1987'      , null  , {encoding:0, year:[1987]}] ,
].forEach(addToBatch);

function addToBatch (test, index) {

  var tagName   = test[0]
    , data      = test[1]
    , value     = test[2]
    , intval    = test[3]
    , info      = test[4];
  
  var FRAME = (Frame.FRAMES[tagName] || Frame.FRAMES_2_2[tagName]);

  var action = ' loading bytes ' + data;

  var testContext = { 
    topic: function () {
      Frame.fromData(FRAME, _23, 0, new Buffer(data, 'hex')).nodeify(this.callback);
    },
    'should have a HashKey': function (err, frame) {
      frame.HashKey.should.be.ok;
    }
  };
  testContext['should have a value \'' + value  + '\''] = function (err, frame) {
    (frame == value).should.be.true;
  };

  if (info['encoding'] == undefined) {
    action += ' without specifying an encoding';
    testContext['should throw if the encoding property is accessed'] = function (err, frame) {
      (function () {
        var encoding = frame.encoding;
      }).should.throwError(/ReferenceError/);
    }
  }

  Object.keys(info).forEach(function (attr) {
    var expectedValue = info[attr];
    var desc = 'should have ' + attr + ': ' + JSON.stringify(expectedValue);

    testContext[desc] = function (err, frame) {
      var underTest;

      if (util.isArray(expectedValue)) {
        // We don't have support for __iter__ on TextFrame, but in this case
        // it's merely sugar to access the text property.
        underTest = frame.text;
      } else {
        underTest = [frame];
        expectedValue = [expectedValue];
      }

      expectedValue.forEach(function (value, idx) {
        var t = underTest[idx];

        //TODO: Handle float values
        // https://github.com/visionmedia/should.js/pull/67
        t[attr].should.equal(value);

        // Mutagen enforces the converse. That is, t should not coerce to a
        // numeric when no intval is provided. No real sensible way at moment
        // to enforce here.
        if (intval) t.valueOf().should.equal(intval); 
      });
    };
  });

  frameTestBatch[tagName + action] = testContext;
}

vows
  .describe('ID3 Frame Reading')
  .addBatch(frameTestBatch)
  .export(module)
