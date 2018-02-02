Pod::Spec.new do |s|

  s.platform = :ios
  s.ios.deployment_target = '8.0'
  s.name         = "EIDStompClient"
  s.authors      = "Adrian Alvarez"
  s.version      = "1.0"
  s.requires_arc = true
  s.summary      = "StompClient based on AKStompClient and updated to Swift 3.0+."

  s.homepage     = "https://gitlab.com/eid-sdk/ios-stomp-client"

  s.license      = { :type => "MIT", :file => "LICENSE" }

  s.source       = { :git => "https://gitlab.com/eid-sdk/ios-stomp-client.git", :tag => "#{s.version}" }

  s.source_files  = "Pod/Classes/**/*.{swift}"

  s.dependency 'SocketRocket', '~> 0.5.1'

end
