
# Ensure this FILE NAME is the name you want for your library
# This is the primary criteria by which your library will be
# found by users of rubygems and sprouts
name = File.basename(__FILE__).split('.').shift

gem_wrap name do |t|
  t.version       = '2.2.5'
  t.summary       = "AsUnit25 is an ActionScript unit test framework for Flash Player 7 and 8 projects"
  t.author        = "Luke Bayes and Ali Mills"
  t.email         = "projectsprouts@googlegroups.com"
  t.homepage      = "http://www.asunit.org"
  t.sprout_spec   =<<EOF
- !ruby/object:Sprout::RemoteFileTarget 
  platform: universal
  filename: asunit3.zip
  library_path: asunit3
  archive_type: zip
  url: http://github.com/lukebayes/asunit/zipball/4.0.3
  md5: 51fa35e79e2d4349d0e0d44652fb00cb
  archive_path: 'lukebayes-asunit-4.0.3-0-ge2af845'
EOF
end
