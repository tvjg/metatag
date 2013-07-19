vows   = require('vows');
should = require('should');

ID3 = require('../lib/id3');
F   = require('../lib/id3/frame');

Frame                = F.Frame;
TextFrame            = F.TextFrame;
NumericTextFrame     = F.NumericTextFrame;
NumericPartTextFrame = F.NumericPartTextFrame;

vows
  .describe('Frame Sanity Checks')
  .addBatch({
    'A TextFrame initialized with {text: \'text\'}': {
      topic: new TextFrame({text:'text'}),
      'should be an instance of TextFrame': function (frame) {
	frame.should.be.an.instanceOf(TextFrame);
      }
    },
    'A NumericTextFrame initialized with {text: \'1\'}': {
      topic: new NumericTextFrame({text:'1'}),
      'should be an instance of NumericTextFrame': function (frame) {
        frame.should.be.an.instanceOf(NumericTextFrame);
      }
    },
    'A NumericPartTextFrame initialized with {text: \'1/2\'}': {
      topic: new NumericPartTextFrame({text:'1/2'}),
      'should be an instance of NumericPartTextFrame': function (frame) {
        frame.should.be.an.instanceOf(NumericPartTextFrame);
      }
    },
    'A TextFrame initialized with {text: \'[\'a\',\'b\']\'}': {
      topic: new TextFrame({text:['a','b']}),
      'should be an instance of TextFrame': function (frame) {
	frame.should.be.an.instanceOf(TextFrame);
      }
    }
  })
  .export(module)
