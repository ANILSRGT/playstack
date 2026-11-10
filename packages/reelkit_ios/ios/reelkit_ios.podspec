#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint reelkit_ios.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'reelkit_ios'
  s.version          = '0.1.0-dev.1'
  s.summary          = 'iOS implementation of ReelKit, built on AVFoundation AVPlayer.'
  s.description      = <<-DESC
iOS implementation of ReelKit, built on AVFoundation AVPlayer.
                       DESC
  s.homepage         = 'https://pub.dev/packages/reelkit_ios'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'ReelKit' => 'reelkit@users.noreply.github.com' }
  s.source           = { :path => '.' }
  s.source_files = 'reelkit_ios/Sources/reelkit_ios/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.9'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'reelkit_ios_privacy' => ['reelkit_ios/Sources/reelkit_ios/PrivacyInfo.xcprivacy']}
end
