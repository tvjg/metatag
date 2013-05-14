var flatiron = require('flatiron');
var path     = require('path');

var Metatag = require('./lib/Metatag');
var app = module.exports = flatiron.app;

app.config.file({ file: path.join(__dirname, 'config', 'config.json') });

app.use(flatiron.plugins.cli, {
  usage: [
    , 'Usage: metatag [file or directory]'
    , 'Metatag will return an array of JSON objects with tag metadata.'
    , ''
    , '-h, --help   Prints this message'
  ]
});

app.cmd(/(.+)/, function() {

  var p = app.argv._[0];
  var tag = new Metatag(p);
  console.log(tag);
});

app.start();
