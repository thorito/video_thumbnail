#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint get_thumbnail_video.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'get_thumbnail_video'
  s.version          = '0.7.3'
  s.summary          = 'A flutter plugin for creating a thumbnail from a local video file or from a video URL.'
  s.description      = <<-DESC
A flutter plugin for creating a thumbnail from a local video file or from a video URL.
                       DESC
  s.homepage         = 'https://github.com/Alberto-Monteiro/video_thumbnail'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Alberto Monteiro' => 'alberto.monteiro@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'get_thumbnail_video/Classes/**/*'
  s.public_header_files = 'get_thumbnail_video/Classes/**/*.h'
  s.dependency 'Flutter'
  s.dependency 'libwebp'
  s.platform = :ios, '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'USER_HEADER_SEARCH_PATHS' => '$(inherited) ${PODS_ROOT}/libwebp/**'
  }
  s.swift_version = '5.0'

  s.resource_bundles = {'get_thumbnail_video_privacy' => ['get_thumbnail_video/Resources/PrivacyInfo.xcprivacy']}
end
