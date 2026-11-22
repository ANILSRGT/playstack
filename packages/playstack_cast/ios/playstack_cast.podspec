Pod::Spec.new do |s|
  s.name             = 'playstack_cast'
  s.version          = '0.1.0'
  s.summary          = 'Chromecast for PlayStack.'
  s.description      = 'Google Cast device picker and remote playback for PlayStack.'
  s.homepage         = 'https://pub.dev/packages/playstack_cast'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'PlayStack' => 'playstack@users.noreply.github.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'google-cast-sdk', '~> 4.8'
  s.platform = :ios, '15.0'
  s.static_framework = true
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.9'
end
