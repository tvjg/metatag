util = require('util');

vows   = require('vows');
should = require('should');

ID3   = require('../lib/id3');
Frame = require('../lib/id3/frame').Frame;

_23 = new ID3(); _23.version = { major: 2, minor: 3, sub: 0 }

var frameTestBatch = {};

[
  [ 'TALB' , '00612f62'             , 'a/b'         , null   , {encoding:0} ],
  [ 'TBPM' , '00313230'             , '120'         , 120    , {encoding:0} ],
  [ 'TCMP' , '0031'                 , '1'           , 1      , {encoding:0} ],
  [ 'TCMP' , '0030'                 , '0'           , 0      , {encoding:0} ],
  [ 'TCOM' , '00612f62'             , 'a/b'         , null   , {encoding:0} ],
  [ 'TCON' , '0028323129446973636f' , '(21)Disco'   , null   , {encoding:0} ],
  [ 'TCOP' , '00313930302063'       , '1900 c'      , null   , {encoding:0} ],
  [ 'TDAT' , '00612f62'             , 'a/b'         , null   , {encoding:0} ],
  [ 'TDEN' , '0031393837'           , '1987'        , null   , {encoding:0, year:[1987]} ],
  [ 'TDOR' , '00313938372d3132'     , '1987-12'     , null   , {encoding:0, year:[1987], month:[12]} ],
  [ 'TDRC' , '003139383700'         , '1987'        , null   , {encoding:0, year:[1987]} ],
  [ 'TDRL' , '00313938370031393838' , '1987,1988'   , null   , {encoding:0, year:[1987,1988]} ],
  [ 'TDTG' , '0031393837'           , '1987'        , null   , {encoding:0, year:[1987]} ],
  [ 'TDLY' , '0031323035'           , '1205'        , 1205   , {encoding:0} ],
  [ 'TENC' , '006120622f632064'     , 'a b/c d'     , null   , {encoding:0} ],
  [ 'TEXT' , '0061206200632064'     , ['a b','c d'] , null   , {encoding:0} ],
  [ 'TFLT' , '004d50472f33'         , 'MPG/3'       , null   , {encoding:0} ],
  [ 'TIME' , '0031323035'           , '1205'        , null   , {encoding:0} ],

  // TODO: Can't find any references to this frame
  // ['TIPL', '\x02\x00a\x00\x00\x00b', [["a", "b"]], '', dict(encoding=2)],

  ['TIT1', '00612f62', 'a/b', null, {encoding: 0}],

  // TIT2 checks misaligned terminator '\x00\x00' across crosses utf16 chars
  ['TIT2', '01fffe38000038', '8\u3800', null, {encoding: 1}],

  [ 'TIT3' , '00612f62'   , 'a/b'  , null , {encoding: 0} ],
  [ 'TKEY' , '0041236d'   , 'A#m'  , null , {encoding: 0} ],
  [ 'TLAN' , '0036323431' , '6241' , null , {encoding: 0} ],
  [ 'TLEN' , '0036323431' , '6241' , 6241 , {encoding: 0} ],

  // TODO: Can't find any references to this frame
  // ['TMCL', '02006100000062', [['a', 'b']], '', {encoding: 2}],

  [ 'TMED' , '006d6564'               , 'med'            , null  , {encoding: 0} ],
  [ 'TMOO' , '006d6f6f'               , 'moo'            , null  , {encoding: 0} ],
  [ 'TOAL' , '00616c62'               , 'alb'            , null  , {encoding: 0} ],
  [ 'TOFN' , '003132203a20626172'     , '12 : bar'       , null  , {encoding: 0} ],
  [ 'TOLY' , '006c7972'               , 'lyr'            , null  , {encoding: 0} ],
  [ 'TOPE' , '006f776e2f6c6963'       , 'own/lic'        , null  , {encoding: 0} ],
  [ 'TORY' , '0031393233'             , '1923'           , 1923  , {encoding: 0} ],
  [ 'TOWN' , '006f776e2f6c6963'       , 'own/lic'        , null  , {encoding: 0} ],
  [ 'TPE1' , '006162'                 , ['ab']           , null  , {encoding: 0} ],
  [ 'TPE2' , '006162006364006566'     , ['ab','cd','ef'] , null  , {encoding: 0} ],
  [ 'TPE3' , '006162006364'           , ['ab','cd']      , null  , {encoding: 0} ],
  [ 'TPE4' , '00616200'               , ['ab']           , null  , {encoding: 0} ],
  [ 'TPOS' , '0030382f3332'           , '08/32'          , 8     , {encoding: 0} ],
  [ 'TPRO' , '0070726f'               , 'pro'            , null  , {encoding: 0} ],
  [ 'TPUB' , '00707562'               , 'pub'            , null  , {encoding: 0} ],
  [ 'TRCK' , '00342f39'               , '4/9'            , 4     , {encoding: 0} ],
  [ 'TRDA' , '0053756e204a756e203132' , 'Sun Jun 12'     , null  , {encoding: 0} ],
  [ 'TRSN' , '0061622f6364'           , 'ab/cd'          , null  , {encoding: 0} ],
  [ 'TRSO' , '006162'                 , 'ab'             , null  , {encoding: 0} ],
  [ 'TSIZ' , '003132333435'           , '12345'          , 12345 , {encoding: 0} ],
  [ 'TSOA' , '006162'                 , 'ab'             , null  , {encoding: 0} ],
  [ 'TSOP' , '006162'                 , 'ab'             , null  , {encoding: 0} ],
  [ 'TSOT' , '006162'                 , 'ab'             , null  , {encoding: 0} ],
  [ 'TSO2' , '006162'                 , 'ab'             , null  , {encoding: 0} ],
  [ 'TSOC' , '006162'                 , 'ab'             , null  , {encoding: 0} ],
  [ 'TSRC' , '003132333435'           , '12345'          , null  , {encoding: 0} ],
  [ 'TSSE' , '003132333435'           , '12345'          , null  , {encoding: 0} ],
  [ 'TSST' , '003132333435'           , '12345'          , null  , {encoding: 0} ],
  [ 'TYER' , '0032303034'             , '2004'           , 2004  , {encoding: 0} ],
  [ 'TXXX' , '0075737200612f620063'   , ['a/b','c']      , null  , {desc: 'usr', encoding: 0} ],

  // 2.2 frames
  [ 'TT1' , '00616200'           , 'ab'     , null , {encoding: 0} ],
  [ 'TT2' , '006162'             , 'ab'     , null , {encoding: 0} ],
  [ 'TT3' , '006162'             , 'ab'     , null , {encoding: 0} ],
  [ 'TP1' , '00616200'           , 'ab'     , null , {encoding: 0} ],
  [ 'TP2' , '006162'             , 'ab'     , null , {encoding: 0} ],
  [ 'TP3' , '006162'             , 'ab'     , null , {encoding: 0} ],
  [ 'TP4' , '006162'             , 'ab'     , null , {encoding: 0} ],
  [ 'TCM' , '0061622f6364'       , 'ab/cd'  , null , {encoding: 0} ],
  [ 'TXT' , '006c7972'           , 'lyr'    , null , {encoding: 0} ],
  [ 'TLA' , '00454e55'           , 'ENU'    , null , {encoding: 0} ],
  [ 'TCO' , '0067656e'           , 'gen'    , null , {encoding: 0} ],
  [ 'TAL' , '00616c62'           , 'alb'    , null , {encoding: 0} ],
  [ 'TPA' , '00312f39'           , '1/9'    , 1    , {encoding: 0} ],
  [ 'TRK' , '00322f38'           , '2/8'    , 2    , {encoding: 0} ],
  [ 'TRC' , '0069737263'         , 'isrc'   , null , {encoding: 0} ],
  [ 'TYE' , '0031393030'         , '1900'   , 1900 , {encoding: 0} ],
  [ 'TDA' , '0032353132'         , '2512'   , null , {encoding: 0} ],
  [ 'TIM' , '0031323235'         , '1225'   , null , {encoding: 0} ],
  [ 'TRD' , '004a756c203137'     , 'Jul 17' , null , {encoding: 0} ],
  [ 'TMT' , '004449472f41'       , 'DIG/A'  , null , {encoding: 0} ],
  [ 'TFT' , '004d50472f33'       , 'MPG/3'  , null , {encoding: 0} ],
  [ 'TBP' , '00313333'           , '133'    , 133  , {encoding: 0} ],
  [ 'TCP' , '0031'               , '1'      , 1    , {encoding: 0} ],
  [ 'TCP' , '0030'               , '0'      , 0    , {encoding: 0} ],
  [ 'TCR' , '004d65'             , 'Me'     , null , {encoding: 0} ],
  [ 'TPB' , '0048696d'           , 'Him'    , null , {encoding: 0} ],
  [ 'TEN' , '004c616d6572'       , 'Lamer'  , null , {encoding: 0} ],
  [ 'TSS' , '006162'             , 'ab'     , null , {encoding: 0} ],
  [ 'TOF' , '0061623a6364'       , 'ab:cd'  , null , {encoding: 0} ],
  [ 'TLE' , '003132'             , '12'     , 12   , {encoding: 0} ],
  [ 'TSI' , '003132'             , '12'     , 12   , {encoding: 0} ],
  [ 'TDY' , '003132'             , '12'     , 12   , {encoding: 0} ],
  [ 'TKE' , '0041236d'           , 'A#m'    , null , {encoding: 0} ],
  [ 'TOT' , '006f7267'           , 'org'    , null , {encoding: 0} ],
  [ 'TOA' , '006f7267'           , 'org'    , null , {encoding: 0} ],
  [ 'TOL' , '006f7267'           , 'org'    , null , {encoding: 0} ],
  [ 'TOR' , '0031383737'         , '1877'   , 1877 , {encoding: 0} ],
  [ 'TXX' , '00646573630076616c' , 'val'    , null , {desc: 'desc', encoding: 0} ],

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
  testContext['should have a value ' + JSON.stringify(value)] = function (err, frame) {
    if (util.isArray(value))
      frame.valueOf().should.eql(value)
    else
      frame.toString().should.equal(value);
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
        // https://github.com/visionmedia/should.js/commit/c364d072d766f52544d8fb755e0c9a20fe2673cd
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
